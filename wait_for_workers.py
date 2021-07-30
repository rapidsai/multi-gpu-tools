import os
import sys
import time
import yaml

from dask.distributed import Client
from dask_cuda.initialize import initialize


expected_workers = int(sys.argv[1])
if expected_workers is None:
    expected_workers = os.environ.get("NUM_WORKERS", 16)


# use scheduler file path from global environment if none
# supplied in configuration yaml
scheduler_file_path = sys.argv[2]

os.environ["UCX_MAX_RNDV_RAILS"] = "1"

initialize(
    enable_tcp_over_ucx=True,
    enable_nvlink=True,
    enable_infiniband=True,
    enable_rdmacm=True,
)

ready = False
while not ready:
    with Client(scheduler_file=scheduler_file_path) as client:
        num_workers = len(client.scheduler_info()['workers'])
        if num_workers < expected_workers:
            print(f'Expected {expected_workers} but got {num_workers}, waiting...')
            sys.stdout.flush()
            time.sleep(5)
        else:
            print(f'Got {num_workers} workers, done.')
            sys.stdout.flush()
            ready = True
