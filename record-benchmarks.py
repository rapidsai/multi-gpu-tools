import glob
import argparse
import pandas as pd
from pathlib import Path

# get the date from the 'latest' sym link with nicer formatting
def get_date_from_path(latest):
    res =  Path(latest).resolve().name#.split('_')[0]
    return res

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

################################################################################

# get the path to latest nightly results directory
# eg. /gpfs/fs1/projects/sw_rapids/users/rratzel/cugraph-results/latest
parser = argparse.ArgumentParser(description="Script used to copy over old benchmark timings")
parser.add_argument('--latest-results', required=True, help='Latest results directory', dest="results_dir")
# might not need this since it's always ${results}/benchmarks
# parser.add_argument('--benchmark-results', required=True, help='Benchmark results directory', dest="bench_dir")
args = parser.parse_args()

results_dir = Path(args.results_dir)
# bench_dir = Path(args.bench_dir)
bench_dir = results_dir / "benchmarks"

# get each of the cugraph benchmark run directories
# eg latest/benchmarks/2-GPU  latest/benchmarks/8-GPU  ... etc
results_dir = bench_dir / "results"

# get results from tonight's runs
all_benchmark_runs = glob.glob(str(bench_dir) + '/*-GPU')
for run in all_benchmark_runs:
    run_type = Path(run).name
    results_file = bench_dir / run_type / 'pytest-results.txt'
    output_file = results_dir / (run_type + ".csv")
    run_date = get_date_from_path('cugraph-results/latest')
    
    # if previous csv files were generated, append tonight's results to the end
    if output_file.exists():
        print("appending regressions to old results")
        existing_df = pd.read_csv(output_file)
        tonight_df = pytest_results_to_df(results_file, run_date)
        pd.concat([existing_df, tonight_df]).to_csv(output_file, index=False)

    # otherwise, create new result file for each successful run
    else:
        if results_file.exists():
            print(f"creating a new results file for {run_type} on {run_date}")
            df = pytest_results_to_df(results_file, run_date)
            df.to_csv(output_file, index=False)
        else:
            # TODO: how to handle results that don't exist? ex. 64-GPU didn't run so no pytest-results.txt file
            print(f"{run_type} results not found")

"""
1. if there are benchmarks from last night, copy over the results.
    -> for todays benchmarks, if the results were generated, append the contents to the end of the csv files
2. if there are no benchmarks from last night, create a blank regressions directory and store tonight's result in new csv files

storing metadata:

*perhaps we can allow devs to add notes when running specific runs. stored in the csv files.
"""