#!/bin/bash
# Copyright (c) 2023, NVIDIA CORPORATION.
# SPDX-License-Identifier: Apache-2.0

# Abort script on first error, undef vars are errors
set -eu

UCX_VERSION_TAG=${1:-"v1.14.x"}
CUDA_HOME=${2:-"/usr/local/cuda"}
# Send any remaining arguments to configure
CONFIGURE_ARGS=${@:2}
PREFIX=${CONDA_PREFIX:-"/usr/local"}

# Setup src dir
rm -rf ucx
git clone https://github.com/openucx/ucx.git
cd ucx
git checkout ${UCX_VERSION_TAG}

# build and install
./autogen.sh
mkdir build-linux && cd build-linux
../contrib/configure-release --prefix=${PREFIX} --with-sysroot --enable-cma \
    --enable-mt --enable-numa --with-gnu-ld --with-rdmacm --with-verbs \
    --with-cuda=${CUDA_HOME} \
    ${CONFIGURE_ARGS}
make -j install
