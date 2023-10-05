import glob
import argparse
import pandas as pd
from pathlib import Path
import platform
from pynvml import smi
import yaml
import os
import math


# read the pytest-results.txt file and return a df in the format we want
def pytest_results_to_df(path, run_date):
    df = pd.read_csv(path, sep=" ", header=None)[[2, 3]]
    date_row = {2: 'date', 3: run_date} # add the run date
    df.loc[1:] = df.loc[:]
    df.loc[0] = date_row
    df = df.T.reset_index(drop=True)
    df.columns = df.iloc[0]
    df = df.drop(df.index[0])
    return df

# convert bytes to biggest denomination
def convert_size(size_bytes):
   if size_bytes == 0:
       return "0B"
   size_name = ("B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB")
   i = int(math.floor(math.log(size_bytes, 1024)))
   p = math.pow(1024, i)
   s = round(size_bytes / p, 2)
   return "%s %s" % (s, size_name[i])

def write_metadata():
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


################################################################################

# get the path to latest nightly results directory
# eg. /gpfs/fs1/projects/sw_rapids/users/rratzel/cugraph-results/latest
parser = argparse.ArgumentParser(description="Script used to copy over old benchmark timings")
parser.add_argument('--latest-results', required=True, help='Latest results directory', dest="results_dir")
args = parser.parse_args()

latest_results_dir = Path(args.results_dir)
run_date = latest_results_dir.resolve().name
bench_dir = latest_results_dir / "benchmarks"

# get each of the cugraph benchmark run directories
# eg latest/benchmarks/2-GPU  latest/benchmarks/8-GPU  ... etc
results_dir = bench_dir / "results"

# get results from tonight's runs
all_benchmark_runs = glob.glob(str(bench_dir) + '/*-GPU')
for run in all_benchmark_runs:
    run_type = Path(run).name
    results_file = bench_dir / run_type / 'pytest-results.txt'
    output_file = results_dir / (run_type + ".csv")
    
    # if previous csv files were generated, append tonight's results to the end
    if output_file.exists():
        existing_df = pd.read_csv(output_file)
        tonight_df = pytest_results_to_df(results_file, run_date)
        pd.concat([existing_df, tonight_df]).to_csv(output_file, index=False)

    # otherwise, create new result file for each successful run
    else:
        if results_file.exists():
            print(f"creating a new results file for {run_type} on {run_date}")
            df = pytest_results_to_df(results_file, run_date)
            df.to_csv(output_file, index=False)

write_metadata()