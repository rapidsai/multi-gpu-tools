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
# Pass this as an option 
#module load cuda/11.0.3
activateCondaEnv

# FIXME: enforce 1st arg is present
NUM_GPUS=$1
NUM_NODES=$(python -c "from math import ceil;print(int(ceil($NUM_GPUS/float($GPUS_PER_NODE))))")
# Creates a string "0,1,2,3" if NUM_GPUS=4, for example, which can be
# used for setting CUDA_VISIBLE_DEVICES on single-node runs.
ALL_GPU_IDS=$(python -c "print(\",\".join([str(n) for n in range($NUM_GPUS)]))")
SCALES=("9" "10" "11")
#ALGOS=(bfs pagerank wcc louvain katz sssp)
ALGOS=(bfs sssp pagerank louvain katz wcc)
#ALGOS=(pagerank)
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


########################################

cd $BENCHMARK_DIR
# create a directory benchmark in workerspace
export RAPIDS_DATASET_ROOT_DIR=$DATASETS_DIR


# Only a node with a SLURM_NODEID 1 or a SNMG can proceed with the rest of the nightly scrip
# This avoid code duplication and a lot of if statement
#if [[ $SLURM_NODEID == 1 || $NUM_NODES == 1 ]]; then
for algo in ${ALGOS[*]}; do
    for scale in ${scales_array[*]}; do

        # Create a log dir per benchamrk file per configuration. This will
        # contain all dask scheduler/worker logs, the stdout/stderr of the
        # benchmark run itself, and any reports (XML, etc.) from the benchmark run
        # for the benchmark file.  Export this var so called scripts will pick
        # it up.
        RELATIVE_LOGS_DIR="${algo}_scale${scale}_num_nodes${NUM_NODES}/${NUM_GPUS}-GPUs"
        export LOGS_DIR="${BENCHMARK_RESULTS_DIR}/${RELATIVE_LOGS_DIR}"
        mkdir -p $LOGS_DIR

        setTee ${LOGS_DIR}/benchmark_output_log.txt
        
        DASK_STARTUP_ERRORCODE=0
        if [[ $NUM_NODES -gt 1 ]]; then

            # Export this for all node. If this is only exported for the with
            # SLURM_NODEID == 1, it causes a renumbering failure
            export UCX_MAX_RNDV_RAILS=1

            # setup the cluster: Each node regardless it is being used as a scheduler
            # is running this part of the script
            bash ${SCRIPTS_DIR}/run-cluster-dask-jobs.sh &

            # Only Node 1 is starting the scheduler 
            if [[ $SLURM_NODEID == 1 ]]; then
                # python tests will look for env var SCHEDULER_FILE when
                # determining what type of Dask cluster to create, so export
                # it here for subprocesses to see.
                export SCHEDULER_FILE=$SCHEDULER_FILE
                
                echo "STARTED" > ${STATUS_FILE}
                # increase the timeout because some nodes take much longer to start
                # their container
                handleTimeout 600 python ${SCRIPTS_DIR}/wait_for_workers.py \
                    --num-expected-workers ${NUM_GPUS} \
                    --scheduler-file-path ${SCHEDULER_FILE}

                DASK_STARTUP_ERRORCODE=$LAST_EXITCODE
            fi
        
        else
            export CUDA_VISIBLE_DEVICES=$ALL_GPU_IDS
            logger "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
        fi

        if [[ $SLURM_NODEID == 1 || $NUM_NODES == 1 ]]; then 
            echo -e "\n>>>>>>>> RUNNING BENCHMARK: $algo - ${NUM_GPUS}-GPUs <<<<<<<<"
            echo -e "\n>>>>>>>>>>>Scale: $scale"

            if [[ $DASK_STARTUP_ERRORCODE == 0 ]]; then
                logger "RUNNING benchmark for algo $algo"
                if echo ${SYMMETRIZED_ALGOS[*]} | grep -q -w "$algo"; then
                    if echo ${WEIGHTED_ALGOS[*]} | grep -q -w "$algo"; then
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph --dask-scheduler-file=$SCHEDULER_FILE --benchmark-dir=$BENCHMARK_RESULTS_DIR
                        else
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph --benchmark-dir=$BENCHMARK_RESULTS_DIR --rmm-pool-size=$WORKER_RMM_POOL_SIZE
                        fi
                    else
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph --unweighted --dask-scheduler-file=$SCHEDULER_FILE --benchmark-dir=$BENCHMARK_RESULTS_DIR
                        else
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --symmetric-graph --unweighted --benchmark-dir=$BENCHMARK_RESULTS_DIR --rmm-pool-size=$WORKER_RMM_POOL_SIZE
                        fi
                    fi
                else
                    if echo ${WEIGHTED_ALGOS[*]} | grep -q -w "$algo"; then
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --dask-scheduler-file=$SCHEDULER_FILE --benchmark-dir=$BENCHMARK_RESULTS_DIR
                        else
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --benchmark-dir=$BENCHMARK_RESULTS_DIR --rmm-pool-size=$WORKER_RMM_POOL_SIZE
                        fi
                    else
                        if [[ $NUM_NODES -gt 1 ]]; then
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --unweighted --dask-scheduler-file=$SCHEDULER_FILE --benchmark-dir=$BENCHMARK_RESULTS_DIR
                        else
                            handleTimeout 180 python ${BENCHMARK_DIR}/python_e2e/main.py --algo=$algo --scale=$scale --unweighted --benchmark-dir=$BENCHMARK_RESULTS_DIR --rmm-pool-size=$WORKER_RMM_POOL_SIZE
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
            # Only MNMG runs use a status file to communicate
            if [[ $NUM_NODES -gt 1 ]]; then
                echo "FINISHED" > ${STATUS_FILE}

                # Wait for the other nodes to read the status file
                sleep 2
                rm -rf ${STATUS_FILE}
            fi
        else
            if [[ $NUM_NODES -gt 1 ]]; then
                # Wait for the node holding both the scheduler and the workers to create the status file
                while [ ! -f "${STATUS_FILE}" ]
                do
                    # FIXME: use Inotify wait to exit the loop once event occurs without having to sleep
                    sleep 1
                done
                # This is targetting the workers node which are not used as schedulers
                # Wait for a signal from the status file only if there are more than 1 node
                until grep -q "FINISHED" "${STATUS_FILE}"
                do
                    # FIXME: use Inotify wait to exit the loop once event occurs without having to sleep
                    sleep 1
                done
                # Pause the supporting nodes to avoid a race conditions with the main node(SLURM_NODEID == 1)
                sleep 2
            fi
        fi

        # At this stage there should be no running processes except /usr/lpp/mmfs/bin/mmsysmon.py
        #pgrep -la dask
        dask_processes=$(pgrep -la dask)
        python_processes=$(pgrep -la python)
        #echo "Node $SLURM_NODEID dask processes: $dask_processes"
        #echo "Node $SLURM_NODEID dask processes: $python_processes"

        if [[ ${#python_processes[@]} -gt 1 || $dask_processes ]]; then
            logger "The client was not shutdown properly, killing dask/python processes for Node $SLURM_NODEID"
            # This can be caused by a job timeout
            pkill python
            pkill dask
            pgrep -la python
            pgrep -la dask
        fi
        
        #pgrep -la python

        # Make sure there is only one process running which is /usr/lpp/mmfs/bin/mmsysmon.py
        # otherwise force kill every process so that the other benchmarks  down the stream won't
        # be affected
        
        sleep 2

    done
done

logger "Exiting \"run-nightly-benchmarks.sh $NUM_GPUS\" with $ERRORCODE"
exit $ERRORCODE
