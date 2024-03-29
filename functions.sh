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

# This file is source'd from script-env.sh to add functions to the
# calling environment, hence no #!/bin/bash as the first line. This
# also assumes the variables used in this file have been defined
# elsewhere.

numargs=$#
args=$*
hasArg () {
    (( ${numargs} != 0 )) && (echo " ${args} " | grep -q " $1 ")
}

logger_prefix=">>>> "
logger () {
    if (( $# > 0 )) && [ "$1" == "-p" ]; then
        shift
        echo -e "${logger_prefix}$@"
    else
        echo -e "$(date --utc "+%D-%T.%N")_UTC${logger_prefix}$@"
    fi
}

# Retry a command at most $1 times until successful, logging $2 on retry.
# This requires scripts to use set +e
retry () {
    max_retries=$1
    msg=$2
    shift 2
    cmd=$@
    eval "$cmd"
    success=$?
    num_retries=0
    while (( success != 0 )) && (( $num_retries < $max_retries )); do
	logger "$msg"
	eval "$cmd"
	success=$?
	(( num_retries++ ))
    done
    # Set a final exit code on non-success that can be checked.
    if (( $success != 0 )); then
	false
    fi
}

# Calling "set_tee outfile" will cause all stdout and stderr of the
# current script to be output to "tee", which outputs to stdout and
# "outfile" simultaneously. This is useful by allowing a script to
# "tee" itself at any point without being called with tee.
origFileDescriptorsSaved=0
set_tee () {
    if [[ $origFileDescriptorsSaved == 0 ]]; then
        # Save off the original file descr 1 and 2 as 3 and 4
        exec 3>&1 4>&2
        origFileDescriptorsSaved=1
    fi
    teeFile=$1
    # Create a named pipe.
    pipeName=$(mktemp -u)
    mkfifo $pipeName
    # Close the currnet 1 and 2 and restore to original (3, 4) in the
    # event this function is called repeatedly.
    exec 1>&- 2>&-
    exec 1>&3 2>&4
    # Start a tee process reading from the named pipe. Redirect stdout
    # and stderr to the named pipe which goes to the tee process. The
    # named pipe "file" can be removed and the tee process stays alive
    # until the fd is closed.
    tee -a < $pipeName $teeFile &
    exec > $pipeName 2>&1
    rm $pipeName
}

# Call this to stop script output from going to "tee" after a prior
# call to set_tee.
unset_tee () {
    if [[ $origFileDescriptorsSaved == 1 ]]; then
        # Close the current fd 1 and 2 which should stop the tee
        # process, then restore 1 and 2 to original (saved as 3, 4).
        exec 1>&- 2>&-
        exec 1>&3 2>&4
    fi
}

# Function for running a command that gets killed after a specific timeout and
# logs a timeout message.
LAST_EXITCODE=0
handle_timeout () {
    _seconds=$1
    eval "timeout --signal=2 --kill-after=60 $*"
    LAST_EXITCODE=$?
    if (( $LAST_EXITCODE == 124 )); then
        logger "ERROR: command timed out after ${_seconds} seconds"
    elif (( $LAST_EXITCODE == 137 )); then
        logger "ERROR: command timed out after ${_seconds} seconds, and had to be killed with signal 9"
    fi
}

waitForSlurmJobsToComplete () {
    ids=$*
    jobs=$(python -c "print(\",\".join(\"$ids\".split()))") # make a comma-separated list
    jobsInQueue=$(squeue --noheader --jobs=$jobs)
    while [[ $jobsInQueue != "" ]]; do
        sleep 2
        jobsInQueue=$(squeue --noheader --jobs=$jobs)
    done
}

# Clones repo from URL specified by $1 to directory $2
# For example:
# "cloneRepo https://github.com/rapidsai/cugraph.git /my/repos/cg"
# results in cugraph being cloned to /my/repos/cg.
# NOTE: This removes any existing cloned repos that match the
# destination.
cloneRepo () {
    repo_url=$1
    repo_name=$(basename $2)
    dest_dir=$(dirname $2)
    mkdir -p $dest_dir
    pushd $dest_dir > /dev/null
    logger "Clone $repo_url in $dest_dir..."
    if [ -d $repo_name ]; then
        rm -rf $repo_name
        if [ -d $repo_name ]; then
            echo "ERROR: ${dest_dir}/$repo_name was not completely removed."
            error 1
        fi
    fi
    git clone $repo_url
    popd > /dev/null
}

keep_last_n_files () {
    n=$1
    pattern=$2

    _files=(${pattern})
    if (( ${#_files[*]} > $n )); then
	_diff=$((${#_files[*]} - $n))
	for ((i=0; i<${_diff}; i++)); do
	    rm -rf ${_files[$i]}
	done
    fi
}

wait_for_file () {
    timeout=$1
    file_name=$2

    logger "waiting for file: $file_name"
    i=0
    while (( i < $timeout )); do
	if [ -e $file_name ]; then
	    logger "file $file_name exists"
	    break
	fi
	sleep 1
	((i++))
    done
    if [ ! -e $file_name ]; then
	logger "timed out waiting for file: $file_name"
	false
    fi
}
