# Copyright (c) 2023, NVIDIA CORPORATION.
#
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
"""
Example usage from bash script called with --foo-bar=www --baz=33 --boo:

set -e  # exit immediately on error
eval_str=$(python getopt.py "foo-bar:,boo,bar,baz:int" "$@")
eval($eval_str)
echo $foo_bar  # prints www
echo $bar  # prints 0
echo $boo  # prints 1
echo $baz  # prints 33
"""

import builtins
from argparse import ArgumentParser


class StderrArgumentParser(ArgumentParser):
    """
    ArgumentParser where all messaging, including help, goes to stderr.
    """
    def _print_message(self, message, file=None):
        super(StderrArgumentParser, self)._print_message(message)


def getopt_to_argparse(prog_name, opt_parse_string, options_list):
    """
    Parse options_list using an ArgumentParser created with opt_parse_string,
    in the style of getopts.

    Return an argparse.Namespace object as normally returned by
    parse_args(). Any errors or help output will be printed to stderr and None
    is returned instead.
    """
    arg_parser = StderrArgumentParser(prog=prog_name)

    for opt_desc in opt_parse_string.split(","):
        if opt_desc == "":
            raise RuntimeError(f"invalid option string: {opt_parse_string}")

        opt_desc = opt_desc.split(":")
        opt_desc_len = len(opt_desc)
        # option with no arg: "name"
        if opt_desc_len == 1:
            name = f"--{opt_desc[0]}"
            arg_parser.add_argument(name, action="store_const", const=1, default=0)

        # required arg: "name:type" or "name:"
        elif opt_desc_len == 2:
            name = f"--{opt_desc[0]}"
            opt_type = getattr(builtins, opt_desc[1] or "str")
            arg_parser.add_argument(name, type=opt_type, required=True)

        # optional arg: "name::type" or "name::"
        elif (opt_desc_len == 3) and (opt_desc[1] == ""):
            name = f"--{opt_desc[0]}"
            opt_type = getattr(builtins, opt_desc[2] or "str")
            arg_parser.add_argument(name, type=opt_type, required=False)

        else:
            raise RuntimeError(f"invalid option string: {opt_parse_string}")
    try:
        return arg_parser.parse_args(options_list)
    except SystemExit as err:
        return None


if __name__ == "__main__":
    import sys
    prog_name = sys.argv[1]
    opt_string = sys.argv[2]
    cli_input = sys.argv[3:]

    exit_code = 1
    argparse_obj = getopt_to_argparse(prog_name, opt_string, cli_input)

    if argparse_obj is not None:
        # Print parsed options to be eval'd by bash
        empty = '""'
        output_strs = [f"{option}={empty if val is None else val}"
                       for (option, val) in vars(argparse_obj).items()]
        print(";".join(output_strs))
        exit_code = 0

    sys.exit(exit_code)
