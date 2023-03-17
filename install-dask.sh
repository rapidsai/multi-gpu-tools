#!/bin/bash
# Copyright (c) 2023, NVIDIA CORPORATION.

# Abort script on first error
set -e

# Always build and install dask and distributed from main
echo "Building/installing dask and distributed from main, using $(python --version), $(pip --version)"
pip install "git+https://github.com/dask/distributed.git@main" --upgrade
pip install "git+https://github.com/dask/dask.git@main" --upgrade
