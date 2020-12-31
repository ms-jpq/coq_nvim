#!/usr/bin/env python3

from sys import path

from kok.consts import RT_DIR

path.append(RT_DIR)


from argparse import ArgumentParser, Namespace

from pynvim import attach
from pynvim_pp.client import run_client

from kok.client import Client


def parse_args() -> Namespace:
    parser = ArgumentParser()
    parser.add_argument("server_socket", default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    nvim = attach("socket", path=args.server_socket)
    code = run_client(nvim, client=Client())
    exit(code)


main()
