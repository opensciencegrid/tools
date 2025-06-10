#!/usr/bin/env python3
"""
make-cas.py <CA_name>

Make a CA.  The CA will be signed with the root CA (unless CA_name is
"root", in which case, it will be self-signed.)
"""

import os
import subprocess as sp
import sys
from argparse import ArgumentParser
from pathlib import Path

# local imports here

TOP_PATH = Path.cwd()
KEY_SIZE = 4096


class CAPaths:
    def __init__(self, CA_name):
        self.CA_name = CA_name

    @property
    def CA_dir(self):
        return TOP_PATH / self.CA_name

    @property
    def CA_crt(self):
        return self.CA_dir / f"certs/{self.CA_name}.crt"

    @property
    def CA_chain(self):
        return self.CA_dir / f"certs/{self.CA_name}-chain.crt"

    @property
    def CA_config(self):
        return self.CA_dir / f"{self.CA_name}-ssl.cnf"

    @property
    def CA_key(self):
        return self.CA_dir / f"private/{self.CA_name}.key"

    @property
    def index_txt(self):
        return self.CA_dir / "index.txt"

    @property
    def serial(self):
        return self.CA_dir / "serial"


def get_args(argv):
    """Parse and validate arguments"""
    parser = ArgumentParser()
    parser.add_argument("name", help="Name of CA; use 'root' to make the root CA")
    args = parser.parse_args(argv[1:])
    return args


def make_new_private_key(CA):
    ret = sp.run(["openssl", "genrsa", str(KEY_SIZE)], stdout=sp.PIPE)
    os.umask(0o077)
    try:
        CA.CA_key.parent.mkdir(exist_ok=True)
        with CA.CA_key.open("wb") as keyfh:
            keyfh.write(ret.stdout)
    finally:
        os.umask(0o022)


def make_new_CA_cert(new_CA, root_CA):
    # fmt:off
    req_args = [
        "-config",  str(root_CA.CA_config),
        "-new",
        "-key",     str(new_CA.CA_key),
        "-out",     str(new_CA.CA_crt),
        "-CAkey",   str(root_CA.CA_key),
        "-CA",      str(root_CA.CA_crt),
    ]
    # fmt:on
    new_CA.CA_chain.parent.mkdir(exist_ok=True)
    sp.run(["openssl", "req"] + req_args)
    with root_CA.CA_crt.open("rb") as root_fh, new_CA.CA_crt.open("rb") as new_fh, new_CA.CA_chain.open("wb") as new_chain_fh:
        new_chain_fh.write(new_fh.read())
        new_chain_fh.write(b"\n")
        new_chain_fh.write(root_fh.read())


def make_root_CA_cert(root_CA):
    req_args = [
        "-config",  str(root_CA.CA_config),
        "-x509",    # implies -new
        "-key",     str(root_CA.CA_key),
        "-out",     str(root_CA.CA_crt),
        "-extensions", "v3_ca",
    ]
    root_CA.CA_crt.parent.mkdir(exist_ok=True)
    sp.run(["openssl", "req"] + req_args)


def main(argv=None):
    args = get_args(argv or sys.argv)
    root_CA = CAPaths("root")
    if not root_CA.CA_dir.is_dir():
        sys.exit(f"root CA dir {root_CA.CA_dir} does not exist or is not a directory")
    if args.name == "root":
        make_new_private_key(root_CA)
        make_root_CA_cert(root_CA)
    else:
        new_CA = CAPaths(args.name)
        if not new_CA.CA_dir.is_dir():
            sys.exit(f"CA dir {new_CA.CA_dir} does not exist or is not a directory")
        make_new_private_key(new_CA)
        make_new_CA_cert(new_CA, root_CA)

    return 0


if __name__ == "__main__":
    sys.exit(main())
