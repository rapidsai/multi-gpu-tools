#!/bin/bash

RAPIDS_MG_TOOLS_DIR=${RAPIDS_MG_TOOLS_DIR:=$(cd $(dirname $0); pwd)}
source ${RAPIDS_MG_TOOLS_DIR}/script-env.sh

module load cuda/11.0.3
activateCondaEnv

# FIXME: enforce 1st arg is present
NUM_GPUS=$1
NUM_NODES=$(python -c "from math import ceil;print(int(ceil($NUM_GPUS/float($GPUS_PER_NODE))))")
# Creates a string "0,1,2,3" if NUM_GPUS=4, for example, which can be
# used for setting CUDA_VISIBLE_DEVICES on single-node runs.
ALL_GPU_IDS=$(python -c "print(\",\".join([str(n) for n in range($NUM_GPUS)]))")

# NOTE: it's assumed TESTING_DIR has been setup elsewhere! For
# example, cronjob.sh calls this script multiple times in parallel, so
# it may set up TESTING_DIR once ahead of time.

export CUPY_CACHE_DIR=${TESTING_DIR}

# Function for running a command that gets killed after a specific timeout and
# logs a timeout message. This also sets ERRORCODE appropriately.
LAST_EXITCODE=0
function handleTimeout {
    seconds=$1
    eval "timeout --signal=2 --kill-after=60 $*"
    LAST_EXITCODE=$?
    if (( $LAST_EXITCODE == 124 )); then
        logger "ERROR: command timed out after ${seconds} seconds"
    elif (( $LAST_EXITCODE == 137 )); then
	logger "ERROR: command timed out after ${seconds} seconds, and had to be killed with signal 9"
    fi
    ERRORCODE=$((ERRORCODE | ${LAST_EXITCODE}))
}

# set +e so the script continues to execute commands even if they return
# non-0. This is needed so all test commands run, but also means the exit code
# for this script must be managed separately in order to indicate that ALL test
# commands passed vs. just the last one.
set +e
set -o pipefail
ERRORCODE=0
RUN_DASK_CLUSTER_PID=""
########################################

cd $TESTING_DIR
export RAPIDS_DATASET_ROOT_DIR=$DATASETS_DIR

for test_file in tests/dask/test_mg_*.py; do

    # FIXME: fix these tests so they dont have to be skipped
    if (echo $test_file | grep -q "betweenness_centrality\|replication"); then
	logger "SKIPPING $test_file"
	continue
    fi

    # Create a log dir per test file per configuration. This will
    # contain all dask scheduler/worker logs, the stdout/stderr of the
    # test run itself, and any reports (XML, etc.) from the test run
    # for the test file.  Export this var so called scripts will pick
    # it up.
    RELATIVE_LOGS_DIR="$(basename --suffix=.py $test_file)/${NUM_GPUS}-GPUs"
    export LOGS_DIR="${RESULTS_DIR}/${RELATIVE_LOGS_DIR}"
    mkdir -p $LOGS_DIR

    setTee ${LOGS_DIR}/pytest_output_log.txt
    echo -e "\n>>>>>>>> RUNNING TESTS FROM: $test_file - ${NUM_GPUS}-GPUs <<<<<<<<"

    if [[ $NUM_NODES -gt 1 ]]; then
	export UCX_MAX_RNDV_RAILS=1
	# python tests will look for env var SCHEDULER_FILE when
	# determining what type of Dask cluster to create, so export
	# it here for subprocesses to see.
	export SCHEDULER_FILE=$SCHEDULER_FILE
        # srun runs a task per node by default
        srun --export="ALL,SCRIPTS_DIR=$SCRIPTS_DIR" --output=/dev/null ${SCRIPTS_DIR}/run-cluster-dask-jobs.sh &
        RUN_DASK_CLUSTER_PID=$!
        python ${SCRIPTS_DIR}/wait_for_workers.py $NUM_GPUS $SCHEDULER_FILE
    else
	export CUDA_VISIBLE_DEVICES=$ALL_GPU_IDS
	logger "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
    fi

    logger "RUNNING: pytest -v -s --cache-clear --no-cov -m '\"not preset_gpu_count\"' $test_file"
    handleTimeout 600 pytest -v -s --cache-clear --no-cov -m '"not preset_gpu_count"' $test_file
    PYTEST_ERRORCODE=$LAST_EXITCODE

    if [[ $NUM_NODES -gt 1 ]]; then
	# Killing the script running all Dask processes on all nodes
	# (scheduler, all workers) will stop those processes. The nodes
	# running those processes will still be allocated to this job,
	# and can/will be used to run the same Dask processes again
	# for the next test.
	kill $RUN_DASK_CLUSTER_PID
    else
	logger "stopping any remaining dask/python processes"
	pkill dask
	pkill python
	pgrep -la dask
	pgrep -la python
    fi

    logger "pytest exited with code: $PYTEST_ERRORCODE, run-py-tests.sh overall exit code is: $ERRORCODE"
    unsetTee

    # Generate a crude report containing the status of each test file.
    test_status_string=PASSED
    if [[ $PYTEST_ERRORCODE != 0 ]]; then
	test_status_string=FAILED
    fi
    echo "$test_file $test_status_string ./${RELATIVE_LOGS_DIR}" >> ${RESULTS_DIR}/pytest-results-${NUM_GPUS}-GPUs.txt
    
    sleep 2
done

logger "Exiting \"run-py-tests.sh $NUM_GPUS\" with $ERRORCODE"
exit $ERRORCODE
