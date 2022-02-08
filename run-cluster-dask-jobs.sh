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

if hasArg --loadModule; then
    module load cuda/11.2.2.0
fi
activateCondaEnv

RUN_SCHEDULER=0

# FIXME: this should not be slurm-specific. Consider a wrapper that
# calls this script for slurm custers.

# Assumption is that this script is called from a multi-node sbatch
# run via srun, with one task per node.  Use SLURM_NODEID 1 for the
# scheduler instead of SLURM_NODEID 0, since the test/benchmark script
# is typically run on 0 and putting the scheduler on 1 helps
# distribute the load (I think, just based on getting OOM errors when
# everything ran on 0).
if [[ $SLURM_NODEID == 1 ]] || [[ $SLURM_JOB_NUM_NODES == 1 ]] || hasArg --scheduler-and-workers; then
    RUN_SCHEDULER=1
fi

# NOTE: if the LOGS_DIR env var is exported from the calling env, it
# will be used by run-dask-process.sh as the log location.
if [[ $RUN_SCHEDULER == 1 ]]; then
    ${SCRIPTS_DIR}/run-dask-process.sh scheduler workers
else
    ${SCRIPTS_DIR}/run-dask-process.sh workers
fi


