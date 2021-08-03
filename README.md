# rapidsai/multi-gpu-tools (rapids-mg-tools)

This repo contains tools for configuring environments and automating
single-node or multi-node, multi-gpu application runs (SNMG or MNMG),
currently consisting of a collection of shell scripts and python
modules for use by such applications.

The tools in this repo are currently aimed at dask-based test and
benchmark applications, but need not be limited to those in the
future.

## Quick start examples  (FIXME: finish this section!)
### Creating a script to run MNMG tests for your project

1) Load the rapids-mg-tools environment into your shell script. This
is boilerplate code to safely source the environment so your scripts
can use the rapids-mg-tools scripts and functions. By specifying your
`PROJECT_DIR`, you can provide your own `config.sh` and `functions.sh`
that can override the defaults in rapids-mg-tools or add custom vars
and functions without having to explicitely source additional files.
file: `/my/project/myscript.sh`:
```
# PROJECT_DIR will default to /my/project but can be overridden by the environment
export PROJECT_DIR=${PROJECT_DIR:-$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)}
if [ -n "$RAPIDS_MG_TOOLS_DIR" ]; then
    source ${RAPIDS_MG_TOOLS_DIR}/script-env.sh
elif [ -n "$(which script-env.sh)" ]; then
    source $(which script-env.sh)
else
    echo "Error: \$RAPIDS_MG_TOOLS_DIR/script-env.sh could not be read nor was script-env.sh in PATH."
    exit 1
fi
```

2) Create a project `config.sh` to customize typical settings such as log dirs, etc.
file: `/my/project/config.sh`:
```
```

3) 