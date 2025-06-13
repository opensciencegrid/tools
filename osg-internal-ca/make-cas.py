#!/usr/bin/env python3
"""
make-cas.py <CA_name>

Make a CA.  The CA will be signed with the root CA (unless CA_name is
"root", in which case, it will be self-signed.)
"""

import os
import shutil
import subprocess as sp
import sys
from argparse import ArgumentParser
from pathlib import Path

TOP_PATH = Path.cwd()
KEY_SIZE = 4096
DAYS = 10000  # by then I'll be dead or retired


class CAPaths:
    def __init__(self, CA_name):
        if not CA_name:
            raise ValueError("CA_name must not be empty")
        self.CA_name = CA_name

    @property
    def CA_dir(self):
        return TOP_PATH / self.CA_name

    @property
    def certs_dir(self):
        return self.CA_dir / "certs"

    @property
    def private_dir(self):
        return self.CA_dir / "private"

    @property
    def CA_crt(self):
        return self.certs_dir / f"{self.CA_name}.crt"

    @property
    def CA_chain(self):
        return self.certs_dir / f"{self.CA_name}-chain.crt"

    @property
    def CA_config(self):
        return self.CA_dir / f"{self.CA_name}-ssl.cnf"

    @property
    def CA_key(self):
        return self.private_dir / f"{self.CA_name}.key"

    @property
    def index_txt(self):
        return self.CA_dir / "index.txt"

    @property
    def serial(self):
        return self.CA_dir / "serial"

    def get_subject_hash(self) -> str:
        """
        Return the 8-hex hash based on the cert subject (OpenSSL 1.0+)
        The cert file must already exist.
        """
        if not self.CA_crt.exists():
            raise FileNotFoundError(self.CA_crt)
        ret = sp.run(
            ["openssl", "x509", "-in", str(self.CA_crt), "-noout", "-subject_hash"],
            check=True,
            encoding="latin-1",
            stdout=sp.PIPE,
        )
        try:
            return ret.stdout.splitlines()[0].strip()
        except IndexError:
            raise RuntimeError("No subject hash returned")

    def get_commonName(self) -> str:
        """
        Return the (first) commonName of the cert.
        The cert file must already exist.
        """
        if not self.CA_crt.exists():
            raise FileNotFoundError(self.CA_crt)
        # fmt:off
        x509_args = [
            "-in",        str(self.CA_crt),
            "-noout",
            "-subject",
            "-nameopt",  "multiline",
        ]
        # fmt:on
        proc1 = sp.Popen(
            ["openssl", "x509"] + x509_args,
            encoding="latin-1",
            stdout=sp.PIPE,
        )

        proc2 = sp.Popen(
            ["awk", "-F", " = ", "/commonName/ { print $2; exit }"],
            encoding="latin-1",
            stdin=proc1.stdout,
            stdout=sp.PIPE,
        )

        try:
            commonName = proc2.communicate()[0].splitlines()[0].strip()
        except IndexError:
            raise RuntimeError("No commonName returned")

        return commonName


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
        CA.private_dir.mkdir(exist_ok=True)
        with CA.CA_key.open("wb") as keyfh:
            keyfh.write(ret.stdout)
        print(f"Private key written to {CA.CA_key}")
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
        "-days",    str(DAYS),
    ]
    # fmt:on
    new_CA.certs_dir.mkdir(exist_ok=True)
    sp.run(["openssl", "req"] + req_args, check=True)
    print(f"Cert written to {new_CA.CA_crt}")
    with root_CA.CA_crt.open("rb") as root_fh, new_CA.CA_crt.open(
        "rb"
    ) as new_fh, new_CA.CA_chain.open("wb") as new_chain_fh:
        new_chain_fh.write(new_fh.read())
        new_chain_fh.write(b"\n")
        new_chain_fh.write(root_fh.read())
    print(f"Cert chain written to {new_CA.CA_chain}")


def make_root_CA_cert(root_CA):
    # fmt:off
    req_args = [
        "-config",      str(root_CA.CA_config),
        "-x509",  # implies -new
        "-key",         str(root_CA.CA_key),
        "-out",         str(root_CA.CA_crt),
        "-extensions",  "v3_ca",
        "-days",        str(DAYS),
    ]
    # fmt:on
    root_CA.certs_dir.mkdir(exist_ok=True)
    sp.run(["openssl", "req"] + req_args, check=True)
    print(f"Cert written to {root_CA.CA_crt}")


def make_hash_symlink(CA: CAPaths):
    """
    Make the symlink named after the subject hashe (the XXXXXXXX.0 symlinks)
    that we have for the certs in /etc/grid-security/certificates.
    The cert file must already exist, otherwise we cannot tell what the hashes
    are.
    """
    longname = CA.get_commonName() + ".crt"
    shutil.copy(CA.CA_crt, CA.certs_dir / longname)
    print(f"Cert copied to {CA.certs_dir / longname}")
    hash_path = CA.certs_dir / (CA.get_subject_hash() + ".0")
    try:
        hash_path.symlink_to(longname)
        print(f"Symlink made at {hash_path}")
    except FileExistsError:
        print(f"Symlink already exists at {hash_path}")


def main(argv=None):
    args = get_args(argv or sys.argv)
    root_CA = CAPaths("root")
    if not root_CA.CA_dir.is_dir():
        sys.exit(f"root CA dir {root_CA.CA_dir} does not exist or is not a directory")
    if args.name == "root":
        make_new_private_key(root_CA)
        make_root_CA_cert(root_CA)
        make_hash_symlink(root_CA)
    else:
        new_CA = CAPaths(args.name)
        if not new_CA.CA_dir.is_dir():
            sys.exit(f"CA dir {new_CA.CA_dir} does not exist or is not a directory")
        make_new_private_key(new_CA)
        make_new_CA_cert(new_CA, root_CA)
        make_hash_symlink(new_CA)

    return 0


if __name__ == "__main__":
    sys.exit(main())
