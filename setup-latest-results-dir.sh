#!/bin/bash
# Copyright (c) 2023, NVIDIA CORPORATION.

# Abort script on first error, undef vars are errors, propagate failures in pipelines
set -eu -o pipefail

RAPIDS_MG_TOOLS_DIR=${RAPIDS_MG_TOOLS_DIR:-$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)}
source ${RAPIDS_MG_TOOLS_DIR}/script-env.sh

usage () {
    echo "Usage: $0 --results-root-dir=<results_root_dir>"
    exit 1
}

results_root_dir=""

params=$(getopt -u -o d: -l results-root-dir: --name "$)" -- "$@")
read -r -a param_array <<< "$params"

i=0
while (( i < ${#param_array[@]} )); do
    case "${param_array[$i]}" in
	-d|--results-root-dir)
	    ((i++)) || true  # required when using set -e
	    results_root_dir=${param_array[$i]}
	    ;;
	--)
	    break
	    ;;
	*)
	    usage
	    ;;
    esac
    ((i++)) || true
done

if [ -z "$results_root_dir" ]; then
    echo "Must specify results_root_dir"
    usage
fi
if [ ! -d $results_root_dir ]; then
    echo "directory $results_root_dir does not exist"
    exit 1
fi

################################################################################
latest_results_dir=${results_root_dir}/latest
testing_results_dir=${latest_results_dir}/${TESTING_RESULTS_DIR_NAME}
benchmark_results_dir=${latest_results_dir}/${BENCHMARK_RESULTS_DIR_NAME}
metadata_file=${latest_results_dir}/${METADATA_FILE_NAME}

mkdir -p ${results_root_dir}/${DATE}

previous_results=$(readlink -f $latest_results_dir)

rm -rf $latest_results_dir
ln -s ${results_root_dir}/${DATE} $latest_results_dir
mkdir -p $testing_results_dir
mkdir -p $benchmark_results_dir

old_asv_dir=$previous_results/benchmarks/asv
if [ -d $old_asv_dir ]; then
    cp -r $old_asv_dir $benchmark_results_dir
fi

# Write paths.sh file for use by other scripts that use the vars set by
# multi-gpu-tools scripts, set to the current values used when setting up the
# results dir.
echo "TESTING_RESULTS_DIR=$testing_results_dir" >> ${latest_results_dir}/paths.sh
echo "BENCHMARK_RESULTS_DIR=$benchmark_results_dir" >> ${latest_results_dir}/paths.sh
# The container may have a /metadata.sh file that can be sourced to set env
# vars with info about the image that can be used in reports, etc.
if [ -e /metadata.sh ]; then
    cp /metadata.sh $metadata_file
    echo "METADATA_FILE=$metadata_file" >> ${latest_results_dir}/paths.sh
else
    echo "METADATA_FILE=\"\"" >> ${latest_results_dir}/paths.sh
fi

# Echo out the latest_results_dir as the last line. This is needed since other
# scripts that call this look for the last line to see the final
# latest_results_dir that was set up (since it may be named using a timestamp
# or some other uniquifier).
echo "Finished setting up latest results dir:"
echo ${latest_results_dir}
