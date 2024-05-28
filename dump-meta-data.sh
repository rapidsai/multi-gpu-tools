#!/bin/bash
# Copyright (c) 2024, NVIDIA CORPORATION.
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

param_vals=$(python3 ${RAPIDS_MG_TOOLS_DIR}/getopt.py $0 "packages:str,from-conda,from-pip" "$@")
eval $param_vals

if (( ($from_conda || $from_pip) == 0 )); then
    echo "ERROR: must specify one of --from-conda or --from-pip"
    exit 1
elif (( ($from_conda && $from_pip) == 1 )); then
    echo "ERROR: must specify only one of --from-conda or --from-pip"
    exit 1
fi

package_list=$(echo $packages | sed 's/,/ /g')
if (( $from_conda == 1 )); then
    for package in $package_list; do
        PACKAGE=$(echo $package | sed 's/[a-z]/\U&/g')
        # output format is: name version build channel
        conda_output=$(conda list | grep "^${package}")
        echo "${PACKAGE}_VERSION=$(echo $conda_output | awk '{print $2}')"
        echo "${PACKAGE}_BUILD=$(echo $conda_output | awk '{print $3}')"
        echo "${PACKAGE}_CHANNEL=$(echo $conda_output | awk '{print $4}')"
    done
elif (( $from_pip == 1 )); then
    for package in $package_list; do
        pip_list_output=$(pip list | grep "^${package}" | head -n 1)
        pip_pkg_name=$(echo $pip_list_output | awk '{print $1}')
        pip_pkg_ver=$(echo $pip_list_output | awk '{print $2}')
        PACKAGE=$(echo $pip_pkg_name | sed 's/[a-z]/\U&/g')
        echo "${PACKAGE}_VERSION=${pip_pkg_ver}"
    done
# else
# TODO: can add --from-source option here
fi
