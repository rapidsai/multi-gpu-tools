#!/bin/bash
# Copyright (c) 2021, NVIDIA CORPORATION.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

RAPIDS_MG_TOOLS_DIR=${RAPIDS_MG_TOOLS_DIR:-$(cd $(dirname $0); pwd)}


source ${RAPIDS_MG_TOOLS_DIR}/script-env.sh

# FIXME: this is project-specific and should happen at the project level.
#module load cuda/11.0.3
#activateCondaEnv



# FIXME: enforce 1st arg is present
NUM_GPUS=$1
NUM_NODES=$(python -c "from math import ceil;print(int(ceil($NUM_GPUS/float($GPUS_PER_NODE))))")
# Creates a string "0,1,2,3" if NUM_GPUS=4, for example, which can be
# used for setting CUDA_VISIBLE_DEVICES on single-node runs.
ALL_GPU_IDS=$(python -c "print(\",\".join([str(n) for n in range($NUM_GPUS)]))")
SCALES=("9" "10" "11")
ALGOS=(bfs sssp pagerank wcc louvain katz)
#ALGOS=(bfs sssp)
SYMMETRIZED_ALGOS=(sssp wcc louvain)
WEIGHTED_ALGOS=(sssp)
scales_array=${SCALES[((NUM_NODES/2))]}
# NOTE: it's assumed BENCHMARK_DIR has been created elsewhere! For
# example, cronjob.sh calls this script multiple times in parallel, so
# it will create, populate, etc. BENCHMARK_DIR once ahead of time.

export CUPY_CACHE_DIR=${BENCHMARK_DIR} #change this after removing the cugraph-benchmark directory

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
# non-0. This is needed so all benchmark commands run, but also means the exit code
# for this script must be managed separately in order to indicate that ALL benchmark
# commands passed vs. just the last one.
set +e
set -o pipefail
ERRORCODE=0
RUN_DASK_CLUSTER_PID=""


########################################

cd $BENCHMARK_DIR
# create a directory benchmark in workerspace
export RAPIDS_DATASET_ROOT_DIR=$DATASETS_DIR


if [[ $NUM_NODES -gt 1 ]]; then
    # Starting the benchmark
    echo "STARTED" > ${STATUS_FILE}
    
    # setup the cluster: Each node regardless of if it will be use as a scheduler
    # too is starting the cluster
    
    bash ${RAPIDS_MG_TOOLS_DIR}/run-cluster-dask-jobs.sh &
    RUN_DASK_CLUSTER_PID=$!
    sleep 25
fi



# Only a node with a SLURM_NODEID 1 or a SNMG can proceed with the rest of the nightly scrip
# This avoid code duplication and a lot of if statement
if [[ $SLURM_NODEID == 1 || $NUM_NODES == 1 ]]; then
    for algo in ${ALGOS[*]}; do
        for scale in ${scales_array[*]}; do

            # Create a log dir per benchamrk file per configuration. This will
            # contain all dask scheduler/worker logs, the stdout/stderr of the
            # benchmark run itself, and any reports (XML, etc.) from the benchmark run
            # for the benchmark file.  Export this var so called scripts will pick
            # it up.
            
            DASK_STARTUP_ERRORCODE=0
            if [[ $NUM_NODES -gt 1 ]]; then

                export SCHEDULER_FILE=$SCHEDULER_FILE

                handleTimeout 120 python ${RAPIDS_MG_TOOLS_DIR}/wait_for_workers.py \
                    --num-expected-workers ${NUM_GPUS} \
                    --scheduler-file-path ${SCHEDULER_FILE} \
                    --timeout-after 60

                DASK_STARTUP_ERRORCODE=$LAST_EXITCODE
            
            else
                export CUDA_VISIBLE_DEVICES=$ALL_GPU_IDS
                logger "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
            fi

            RELATIVE_LOGS_DIR="${algo}_scale${scale}_num_nodes${NUM_NODES}/${NUM_GPUS}-GPUs"
            export LOGS_DIR="${BENCHMARK_RESULTS_DIR}/${RELATIVE_LOGS_DIR}"
            mkdir -p $LOGS_DIR

            setTee ${LOGS_DIR}/benchmark_output_log.txt
            echo -e "\n>>>>>>>> RUNNING BENCHMARK: $algo - ${NUM_GPUS}-GPUs <<<<<<<<"
            echo -e "\n>>>>>>>>>>>Scale: $scale"

            if [[ $DASK_STARTUP_ERRORCODE == 0 ]]; then
                logger "RUNNING benchmark for algo $algo"
                if echo ${SYMMETRIZED_ALGOS[*]} | grep -q -w "$algo"; then
                    if echo ${WEIGHTED_ALGOS[*]} | grep -q -w "$algo"; then
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph --dask-scheduler-file=$SCHEDULER_FILE
                        else
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph
                        fi
                    else
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph --unweighted --dask-scheduler-file=$SCHEDULER_FILE
                        else
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph --unweighted
                        fi
                    fi
                else
                    if echo ${WEIGHTED_ALGOS[*]} | grep -q -w "$algo"; then
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --dask-scheduler-file=$SCHEDULER_FILE
                        else
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale
                        fi
                    else
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --unweighted --dask-scheduler-file=$SCHEDULER_FILE
                        else
                            handleTimeout 600 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --unweighted
                        fi
                    fi
                fi 
                BENCHMARK_ERRORCODE=$LAST_EXITCODE
            else
                logger "Dask processes failed to start, not running benchmarks for $algo."
            fi

            

            if [[ $DASK_STARTUP_ERRORCODE == 0 ]]; then
                logger "python exited with code: $BENCHMARK_ERRORCODE, run-nightly-benchmark.sh overall exit code is: $ERRORCODE"
            fi

            unsetTee

            # Generate a crude report containing the status of each benchmark file.
            
            benchmark_status_string=PASSED
            if [[ $BENCHMARK_ERRORCODE != 0 ]]; then
                benchmark_status_string=FAILED
            fi
            echo "Benchmarking $algo $benchmark_status_string ./${RELATIVE_LOGS_DIR}" >> ${BENCHMARK_RESULTS_DIR}/benchmark-results-${NUM_GPUS}-GPUs.txt
            

        done
    done

# Only MNMG uses a status file to communicate 
    if [[ $NUM_NODES -gt 1 ]]; then
        echo "FINISHED" > ${STATUS_FILE}
        sleep 2
        rm -rf ${STATUS_FILE}
    fi

else
    # This is targetting the workers node which are not used as schedulers
    # Wait for a signal from the status file only if there are more than 1 node
    if [[ $NUM_NODES -gt 1 ]]; then
        until grep -q "FINISHED" "${STATUS_FILE}"
        do
            sleep 1
        done
        # The nodes not being used as schedulers need to wait until the node
        # that does write to the scheduler
        sleep 5
    fi
fi


# FIXME: This script is using the same cluster and scheduler instead of
# creating a new one
if [[ $NUM_NODES -gt 1 ]]; then
    # Killing the script running all Dask processes on all nodes
    # (scheduler, all workers) will stop those processes. The nodes
    # running those processes will still be allocated to this job,
    # and can/will be used to run the same Dask processes again
    # for the next benchmark.

    # FIXME: Killing the Process ID of run-cluster-dask-jobs.sh is not working
    # the same way as in the non container based
    kill $RUN_DASK_CLUSTER_PID

    pkill dask
    pkill python
    pgrep -la dask
    pgrep -la python
    
    #kill dask
    #pkill python
else
    #logger "stopping any remaining dask/python processes"
    pkill dask
    pkill python
    pgrep -la dask
    pgrep -la python
fi

sleep 5


logger "Exiting \"run-nightly-benchmarks.sh $NUM_GPUS\" with $ERRORCODE"

exit $ERRORCODE
