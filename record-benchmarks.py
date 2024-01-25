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

import argparse
import glob
from itertools import groupby
import math
import os
from pathlib import Path

from jinja2 import Environment, FileSystemLoader
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import platform
from pynvml import smi
import yaml


def get_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        '--latest-results',
        required=True,
        help='Latest results directory'
    )

    parser.add_argument(
        '--template-dir',
        required=True,
        help='Directory containing html templates'
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

def _convert_size(size_bytes):
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

def _group_integers_into_ranges(lst):
    ranges = []
    for k, g in groupby(enumerate(lst), lambda i_x: i_x[0] - i_x[1]):
        group = list(map(lambda i_x: i_x[1], g))
        if len(group) == 1:
            ranges.append((group[0], group[0]))
        else:
            ranges.append((group[0],group[-1]))
    return ranges

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

def remove_path_prefix(df):
    """Remove the './' prefix from df columns"""
    y_cols = df.columns.drop(["date"])
    for col in y_cols:
        newname = col[2:]
        df.rename(columns={col: newname}, inplace=True)
    return df


def plot_benchmark_results(path, dest):
    """
    Reads the results and processes them inside a DF for plotting purposes.
    - Remove invalid dtypes
    - Convert all columns except 'date' to floats
    Then, generate individual plots of each nightly benchmark result and save them as an image.

    Parameters:
    - path (str): the path to the .csv file to be plotted.
    - dest (str): the path to save the plots in
    """
    df = pd.read_csv(path, sep=',')
    x_col = 'date'
    df = remove_path_prefix(df)

    save_path = Path(dest)
    if not save_path.exists():
        save_path.mkdir(parents=True)

    for y_col in df.columns.drop(x_col):
        failed_rows = df[df[y_col].isin(['FAILED']) | pd.isna(df[y_col])].index
        skipped_rows = df[df[y_col].isin(['SKIPPED'])].index

        red_ranges = _group_integers_into_ranges(failed_rows)
        yellow_ranges = _group_integers_into_ranges(skipped_rows)

        df[y_col].replace(['SKIPPED', 'FAILED'], [np.nan, np.nan], inplace=True)
        df[y_col] = df[y_col].astype(float)

        plt_size = (30,4)
        plt.figure(figsize=plt_size)
        plt.plot(df[x_col], df[y_col], marker='.', linewidth=3, markersize=14)

        if red_ranges:
            for start, end in red_ranges:
                plt.axvspan(start, end, facecolor='#e0243a', alpha=0.4)
        if yellow_ranges:
            for start, end in yellow_ranges:
                plt.axvspan(start, end, facecolor='#e09b24', alpha=0.4)

        plt.xticks([])
        plt.rc('ytick', labelsize=18)
        plt.grid(True, linestyle='--', color='gray', alpha=0.1)
        plt.tight_layout()
        plt.savefig(save_path / (y_col + '.jpg'), dpi=300)
        plt.close()


def render_template(template_dir, name, contents):
    """
    Render an HTML template and replace missing fields.

    Parameters:
    - template_dir (pathlib Path obj): directory containing templates.
    - name (str): name of the template.
    - contents (dict): fields being used to fill out the template.

    Returns:
    str: the rendered contents of an HTML file.
    """
    if not template_dir.exists():
        raise RuntimeError(f'{template_dir} does not exist')

    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template(name)
    rendered_content = template.render(contents)

    return rendered_content


################################################################################

# call __main__
if __name__ == '__main__':
    args = get_args()

    latest_results_dir = Path(args.latest_results)
    template_dir = Path(args.template_dir)
    run_date = latest_results_dir.resolve().name
    bench_dir = latest_results_dir / "benchmarks"

    # get each of the cugraph benchmark run directories
    # eg latest/benchmarks/2-GPU  latest/benchmarks/8-GPU  ... etc
    results_dir = bench_dir / "results"
    all_benchmark_runs = glob.glob(str(bench_dir) + '/*-GPU')

    # RECORD NIGHTLY RESULTS
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

        # otherwise, create new result file for each successful run
        else:
            if results_file.exists():
                print(f"creating a new results file for {run_type} on {run_date}")
                df = pytest_results_to_df(results_file, run_date)
                df.to_csv(output_file, index=False)


    csv_files = [file for file in results_dir.iterdir() if file.is_file() and file.suffix == ".csv"]

    # GENERATE HTML PLOTS
    for file in csv_files:
        run_type = file.name[:-4]
        plot_dir = results_dir / 'plots'  / run_type

        df = pd.read_csv(file)
        last_date = df.iloc[-1]['date']
        contents = {
            'run_type': run_type,
            'run_date': last_date,
            'table_contents': ''
        }

        df = remove_path_prefix(df)
        df = df.drop('date', axis=1).apply(pd.to_numeric, errors='coerce')
        
        last_row = df.iloc[-1]
        last_30_rows = df.tail(30)
        last_30_avg = last_30_rows.mean(numeric_only=True)

        plot_benchmark_results(file, plot_dir)

        # start filling in the HTML table
        for plot in plot_dir.iterdir():
            file_name = plot.name
            if not file_name.endswith('.jpg'):
                continue # skip the .html file

            benchmark_name = file_name[:-4]
            image_path = f'plots/{run_type}/{file_name}'

            # last recorded result
            last_res = last_row[benchmark_name]
            if np.isnan(last_res):
                last_res = "n/a"
            else:
                last_res = round(float(last_res), 4)
            
            # 30 day avg
            last_30 = last_30_avg[benchmark_name]
            if np.isnan(last_30):
                last_30 = "n/a"
            else:
                last_30 = round(float(last_30), 4)

            contents['table_contents'] += f'<tr><td><text>{benchmark_name}<br>{last_res}<br>{last_30}</text></td><td><img src="{image_path}" alt="{image_path}"></td></tr>\n'

        # render results table with plots
        rendered_template = render_template(template_dir, 'benchmark-results-plot.html', contents)
        with open(results_dir / (run_type + '.html'), 'w') as html_file:
            html_file.write(rendered_template)
