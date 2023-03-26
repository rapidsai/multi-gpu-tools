#!/bin/bash
# Copyright (c) 2023, NVIDIA CORPORATION.

# Abort script on first error, undef vars are errors
set -eu

# Must ensure PROJECT_DIR is exported first then load rapids-mg-tools env
export PROJECT_DIR=${PROJECT_DIR:-$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)}
if [ -n "$RAPIDS_MG_TOOLS_DIR" ]; then
    source ${RAPIDS_MG_TOOLS_DIR}/script-env.sh
else
    echo "Error: \$RAPIDS_MG_TOOLS_DIR/script-env.sh could not be read."
    exit 1
fi

# Creates a unique results dir based on date, then links the common
# results dir name to it.
mkdir -p ${RESULTS_ARCHIVE_DIR}/${DATE}

# Store the target of $RESULTS_DIR before $RESULTS_DIR get linked to a
# different dir
previous_results=$(readlink -f $RESULTS_DIR)

rm -rf $RESULTS_DIR
ln -s ${RESULTS_ARCHIVE_DIR}/${DATE} $RESULTS_DIR
mkdir -p $TESTING_RESULTS_DIR
mkdir -p $BENCHMARK_RESULTS_DIR

old_asv_dir=$previous_results/benchmarks/asv
if [ -d $old_asv_dir ]; then
    cp -r $old_asv_dir $BENCHMARK_RESULTS_DIR
fi

# The container may have a /metadata.sh file that can be sourced to set env
# vars with info about the image that can be used in reports, etc.
if [ -n /metadata.sh ]; then
    cp /metadata.sh $METADATA_FILE
fi

# Write paths.sh file for use by other scripts that use the vars set by
# multi-gpu-tools scripts, set to the current values used when setting up the
# results dir.
echo "TESTING_RESULTS_DIR=$TESTING_RESULTS_DIR" >> ${RESULTS_DIR}/paths.sh
echo "BENCHMARK_RESULTS_DIR=$BENCHMARK_RESULTS_DIR" >> ${RESULTS_DIR}/paths.sh
echo "METADATA_FILE=$METADATA_FILE" >> ${RESULTS_DIR}/paths.sh

# Echo out the RESULTS_DIR as the last line. This is needed since other scripts
# that call this look for the last line to see the final RESULTS_DIR that was
# set up (since it may be named using a timestamp or some other uniquifier).
echo "Finished setting up results dir:"
echo ${RESULTS_DIR}
