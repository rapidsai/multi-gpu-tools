# Copyright (c) 2023, NVIDIA CORPORATION.
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

import argparse
import glob
import math
import os
from pathlib import Path

import yaml
import pandas as pd
import platform
from pynvml import smi


def get_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        '--latest-results',
        required=True,
        help='Latest results directory',
        dest="results_dir"
    )

    return parser.parse_args()

def pytest_results_to_df(path, run_date):
    """
    Reads the most recent pytest results file and stores them in a DataFrame.

    Parameters:
    - path (str): the path to the pytest-results.txt file.
    - run_date (str): the UTC formatted date of the benchmark run.

    Returns:
    df: a pandas DataFrame containing one row of all benchmark results from the last run.
    """
    df = pd.read_csv(path, sep=" ", header=None)
    df[3] = df[3].astype('object')
    # preserve failed/skipped statuses
    df.loc[df[1] == 'FAILED', 3] = 'FAILED'
    df.loc[df[1] == 'SKIPPED', 3] = 'SKIPPED'
    df = df[[2, 3]]
    # add the run date
    date_row = {2: 'date', 3: run_date}
    df.loc[1:] = df.loc[:]
    df.loc[0] = date_row
    df = df.T.reset_index(drop=True)
    df.columns = df.iloc[0]
    df = df.drop(df.index[0])
    return df

def convert_size(size_bytes):
    """
    Convert bytes to biggest denomination.
    
    Parameters:
    size_bytes (str): the number of bytes to be converted.

    Returns:
    (str): the properly rounded size denomination.
    """
    if size_bytes == 0:
        return "0B"
    size_name = ("B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB")
    i = int(math.floor(math.log(size_bytes, 1024)))
    p = math.pow(1024, i)
    s = round(size_bytes / p, 2)
    return "%s %s" % (s, size_name[i])

def write_metadata():
    """ Writes some metadata information to a metadata.yaml file. """
    uname = platform.uname()
    python_ver = 'python_ver: ' + platform.python_version()
    cuda_version = os.system("nvcc --version | sed -n 's/^.*release \([0-9]\+\.[0-9]\+\).*$/\1/p'")
    # get info for all gpu devices
    smi.nvmlInit()
    num_gpus = smi.nvmlDeviceGetCount()
    gpu_info = []
    for i in range(num_gpus):
        gpuDeviceHandle = smi.nvmlDeviceGetHandleByIndex(i)
        gpuType = smi.nvmlDeviceGetName(gpuDeviceHandle).decode()
        gpuRam = smi.nvmlDeviceGetMemoryInfo(gpuDeviceHandle).total
        gpu_info.append([gpuType, convert_size(gpuRam)])
    meta = {
        'os_name': uname[0],
        'node_name': uname[1],
        'os_release': uname[2],
        'os_version': uname[3],
        'machine_hw': uname[4],
        'python_version': platform.python_version(),
        'cuda_version': cuda_version,
        'num_gpus': num_gpus,
        'gpu_info': gpu_info,
    }
    with open(results_dir / 'meta.yaml', 'w+') as file:
        yaml.dump(meta, file, sort_keys=False)


def remove_path_from_title(df):
    """
    Strip the './' prefix from the benchmark names.

    Parameters:
    df (DataFrame): a pandas DataFrame that contains the raw benchmark names from the pytest-results.txt file.

    Returns:
    df: a new DataFrame with the fixed column names.
    """
    columns = df.columns.drop(["date"])
    for col in columns:
        newname = col[2:]
        df.rename(columns={col: newname}, inplace=True)
    return df

def get_last_recorded_date(df):
    """
    Return the last recorded date from a results df

    Parameters:
    df (DataFrame): results df

    Returns:
    a DateTime object of the most recent-run
    """
    last_row_date= df.iloc[-1]['date']
    return datetime.strptime(last_row_date, '%Y%m%d_%H%M%S_UTC')

################################################################################

# call __main__ function
if __name__ == '__main__':
    args = get_args()

    latest_results_dir = Path(args.results_dir)
    run_date = latest_results_dir.resolve().name
    bench_dir = latest_results_dir / "benchmarks"

    # get each of the cugraph benchmark run directories
    # eg latest/benchmarks/2-GPU  latest/benchmarks/8-GPU  ... etc
    results_dir = bench_dir / "results"

    # RECORD NIGHTLY RESULTS
    all_benchmark_runs = glob.glob(str(bench_dir) + '/*-GPU')
    for run in all_benchmark_runs:
        run_type = Path(run).name
        results_file = bench_dir / run_type / 'pytest-results.txt'
        output_file = results_dir / (run_type + ".csv")
        
        # if previous csv files were generated, append tonight's results to the end
        if output_file.exists():
            existing_df = pd.read_csv(output_file)
            tonight_df = pytest_results_to_df(results_file, run_date)
            res = pd.concat([existing_df, tonight_df])
            res.to_csv(output_file, index=False)
            res.to_html(results_dir / (run_type + '.html'))

        # otherwise, create new result file for each successful run
        else:
            if results_file.exists():
                print(f"creating a new results file for {run_type} on {run_date}")
                df = pytest_results_to_df(results_file, run_date)
                df.to_csv(output_file, index=False)
                df.to_html(results_dir / (run_type + '.html'), index=False)


    csv_files = [file for file in results_dir.iterdir() if file.is_file() and file.suffix == ".csv"]
    # GENERATE HTML PLOTS
    for file in csv_files:
        df = pd.read_csv(csv_files[0], sep=',')
        df = remove_path_from_title(df)
        df.replace(['SKIPPED', 'FAILED'], [np.nan, np.nan], inplace=True)
        # Convert all columns except 'date' to floats
        float_columns = [col for col in df.columns if col != 'date']
        df[float_columns] = df[float_columns].astype(float)