#!/bin/bash
# Copyright (c) 2021-2023, NVIDIA CORPORATION.
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

# Abort script on first error, undef vars are errors, propagate failures in pipelines
set -eu -o pipefail

RAPIDS_MG_TOOLS_DIR=${RAPIDS_MG_TOOLS_DIR:-$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)}
source ${RAPIDS_MG_TOOLS_DIR}/script-env.sh

if hasArg -h || hasArg --help; then
    echo "$0 [<option>...]
where <option> is:
  #--from-source  - Assume a from-source build and use git to extract meta-data.
  --from-conda   - Assume a conda install and use conda to extract meta-data.
  --from-pip     - Assume a pip install and use pip to extract meta-data.
  --help | -h    - Print this message and exit.
"
    exit 0
fi

PROJECT_VERSION=""
PROJECT_BUILD=""
PROJECT_CHANNEL=""
PROJECT_REPO_URL=""
PROJECT_REPO_BRANCH=""
PROJECT_REPO_TIME=""

if hasArg --from-conda; then
    # output format is: name version build channel
    conda_output=$(conda list | grep "^${PRIMARY_CONDA_PACKAGE_NAME}")
    PROJECT_VERSION=$(echo $conda_output | awk '{print $2}')
    PROJECT_BUILD=$(echo $conda_output | awk '{print $3}')
    PROJECT_CHANNEL=$(echo $conda_output | awk '{print $4}')

# elif hasArg --from-source; then
#     # FIXME: this assumes the sources are always in
#     # ${WORKSPACE}/${REPO_DIR_NAME}. That should be the default and a
#     # --source-dir option should be added to override.
#     PROJECT_VERSION=$(cd ${WORKSPACE}/${REPO_DIR_NAME}; git rev-parse HEAD)
#     PROJECT_REPO_URL=$(cd ${WORKSPACE}/${REPO_DIR_NAME}; git config --get remote.origin.url)
#     PROJECT_REPO_BRANCH=$(cd ${WORKSPACE}/${REPO_DIR_NAME}; git rev-parse --abbrev-ref HEAD)
#     PROJECT_REPO_TIME=$(cd ${WORKSPACE}/${REPO_DIR_NAME}; git log -n1 --pretty='%ct' ${PROJECT_VERSION})

elif hasArg --from-pip; then
    # FIXME: write this
    PROJECT_VERSION="FIXME-for-pip"
    PROJECT_BUILD="FIXME-for-pip"
    PROJECT_CHANNEL="FIXME-for-pip"

else
    echo "ERROR: must specify either --from-source or --from-conda or --from-pip"
    exit 1
fi

echo "PROJECT_VERSION=\"$PROJECT_VERSION\""
echo "PROJECT_BUILD=\"$PROJECT_BUILD\""
echo "PROJECT_CHANNEL=\"$PROJECT_CHANNEL\""
echo "PROJECT_REPO_URL=\"$PROJECT_REPO_URL\""
echo "PROJECT_REPO_BRANCH=\"$PROJECT_REPO_BRANCH\""
echo "PROJECT_REPO_TIME=\"$PROJECT_REPO_TIME\""
