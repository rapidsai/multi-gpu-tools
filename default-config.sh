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

THIS_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
# Most are defined using the bash := or :- syntax, which means they
# will be set only if they were previously unset. The project config
# is loaded first, whic hgives it the opportunity to override anything
# in this file that uses that syntax.  If there are variables in this
# file that should not be overridded by a project, then they will
# simply not use that syntax and override, since these variables are
# read last.
RAPIDS_MG_TOOLS_DIR=${RAPIDS_MG_TOOLS_DIR:-$THIS_DIR}
OUTPUT_DIR=${OUTPUT_DIR:-$(pwd)}
RESULTS_ARCHIVE_DIR=${RESULTS_ARCHIVE_DIR:-${OUTPUT_DIR}/results}
RESULTS_DIR=${RESULTS_DIR:-${RESULTS_ARCHIVE_DIR}/latest}
METADATA_FILE=${METADATA_FILE:-${RESULTS_DIR}/metadata.sh}
WORKSPACE=${WORKSPACE:-${OUTPUT_DIR}/workspace}
TESTING_DIR=${TESTING_DIR:-${WORKSPACE}/testing}
SCRIPTS_DIR=$RAPIDS_MG_TOOLS_DIR

# These should be oerridden by the project config!
CONDA_ENV=${CONDA_ENV:-rapids}
PRIMARY_CONDA_PACKAGE_NAME=${PRIMARY_CONDA_PACKAGE_NAME:-condapackage}
REPO_DIR_NAME=${REPO_DIR_NAME:-repo}

GPUS_PER_NODE=${GPUS_PER_NODE:-8}
WORKER_RMM_POOL_SIZE=${WORKER_RMM_POOL_SIZE:-12G}

# There is no default for this, it is here for documentation purposes
# since RAPIDS_DATASET_ROOT_DIR will be set to it in various test
# scripts (which may enforce that it be set), and it should be set by
# the project config.
DATASETS_DIR=$DATASETS_DIR

BUILD_LOG_FILE=${RESULTS_DIR}/build_log.txt
SCHEDULER_FILE=${WORKSPACE}/dask-scheduler.json

DATE=$(date --utc "+%Y-%m-%d_%H:%M:%S")_UTC
ENV_EXPORT_FILE=${WORKSPACE}/$(basename ${CONDA_ENV})-${DATE}.txt

# There are no defaults for these, they are here for documentation
# purposes since they will be used by various reporting scripts (which
# may enforce that they be set), and they should be set by the project
# config.
WEBHOOK_URL=$WEBHOOK_URL
S3_FILE_PREFIX=$S3_FILE_PREFIX
S3_URL_PREFIX=$S3_URL_PREFIX
