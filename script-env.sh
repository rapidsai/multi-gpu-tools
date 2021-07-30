# This file is meant to be source'd by other scripts to add variables
# and functions to the calling environment, hence no #!/bin/bash as
# the first line.

# Read the config for the project, if possible.  The project config
# takes precedence, and anything missing from the project config is
# set here.
# Projects should always call this script to ensure a complete set of
# script vars and functions are available.
if [ -n "$PROJECT_DIR" ]; then
    if [ -e ${PROJECT_DIR}/config.sh ]; then
	source ${PROJECT_DIR}/config.sh
    fi
    if [ -e ${PROJECT_DIR}/functions.sh ]; then
	source ${PROJECT_DIR}/functions.sh
    fi
fi

THIS_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

source ${THIS_DIR}/default-config.sh
source ${THIS_DIR}/functions.sh
