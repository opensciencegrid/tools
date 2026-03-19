#!/usr/bin/env python3
"""
run-distrepos

Run osg-koji dist-repo tasks with the correct arguments against a subset of
Koji tags.  Note that this uses pre-defined tag data (in the TAGDATA var).
"""

import pprint
import re
import subprocess as sp
import sys
from argparse import ArgumentParser


def ask_yn(prompt: str):
    if not sys.stdin.isatty():
        return False
    reply = ""
    while not (reply.startswith("y") or reply.startswith("n")):
        print(prompt, "(y/n)", end=" ")
        try:
            reply = input()
        except EOFError:
            return False
    return reply.startswith("y")


def filter_tags(pattern):
    matching = [tag for tag in TAGDATA if pattern.search(tag[0])]
    matching_names = [tag[0] for tag in matching]

    print("Matching tags: ")
    pprint.pprint(matching_names)

    return matching


def run_distrepo(tag: str, key: str, non_latest: bool):
    sp.run(
        "osg-koji dist-repo --wait --with-src "
        " --split-debuginfo --write-signed-rpms "
        + ("--non-latest " if non_latest else " ")
        + tag
        + " "
        + key,
        shell=True,
    )


def get_parser():
    """
    Return an argument parser.
    """
    parser = ArgumentParser()
    parser.add_argument(
        "regex",
        default="",
        nargs="?",
        help="Regex to match the tags to regen against (not anchored). "
        "Will prompt interactively if not specified.",
    )
    parser.add_argument(
        "-y",
        "--noconfirm",
        action="store_true",
        help="Do not ask for confirmation.",
    )
    return parser


def run_distrepo_on_matching(matching):
    for tag in matching:
        name = tag[0]
        key = tag[1]
        latest = tag[2] == "latest"

        run_distrepo(name, key, non_latest=not latest)


def main(argv=None):
    parser = get_parser()
    args = parser.parse_args((argv or sys.argv)[1:])
    if args.regex:
        pattern = re.compile(args.regex)
        matching = filter_tags(pattern)
        if not matching:
            print("no tags match")
            return 1
        if args.noconfirm or ask_yn("Run distrepo on the above tags?"):
            run_distrepo_on_matching(matching)

    else:
        if args.noconfirm:
            parser.error("You must specify a regex if you use -y")
        if not sys.stdin.isatty():
            parser.error("You must specify a pattern if not on a tty")
        while True:
            try:
                regex = input("Enter regex: ").strip()
            except EOFError:
                print("EOF, exiting")
                return 1
            except KeyboardInterrupt:
                print("Interrupted, exiting")
                return 3
            if not regex:
                print("Empty pattern, exiting")
                return 1
            try:
                pattern = re.compile(regex)
            except ValueError:
                print("invalid regex, try again")
                continue
            matching = filter_tags(pattern)
            if ask_yn("Run distrepo on the above tags?"):
                run_distrepo_on_matching(matching)
                break

    return 0


# fmt: off
# TAGDATA fields are: tag, GPG key hash, whether to also include non-latest RPMs
TAGDATA = [
    ("osg-23-el8-contrib"               , "92897c00" , "latest")    ,
    ("osg-23-el8-empty"                 , "92897c00" , "latest")    ,
    ("osg-23-el9-contrib"               , "92897c00" , "latest")    ,
    ("osg-23-el9-empty"                 , "92897c00" , "latest")    ,
    ("osg-23-internal-el8-development"  , "4d4384d0" , "latest")    ,
    ("osg-23-internal-el8-release"      , "92897c00" , "non-latest"),
    ("osg-23-internal-el9-development"  , "4d4384d0" , "latest")    ,
    ("osg-23-internal-el9-release"      , "92897c00" , "non-latest"),
    ("osg-23-main-el8-development"      , "4d4384d0" , "latest")    ,
    ("osg-23-main-el8-release"          , "92897c00" , "non-latest"),
    ("osg-23-main-el8-testing"          , "92897c00" , "non-latest"),
    ("osg-23-main-el9-development"      , "4d4384d0" , "latest")    ,
    ("osg-23-main-el9-release"          , "92897c00" , "non-latest"),
    ("osg-23-main-el9-testing"          , "92897c00" , "non-latest"),
    ("osg-23-upcoming-el8-development"  , "4d4384d0" , "latest")    ,
    ("osg-23-upcoming-el8-release"      , "92897c00" , "non-latest"),
    ("osg-23-upcoming-el8-testing"      , "92897c00" , "non-latest"),
    ("osg-23-upcoming-el9-development"  , "4d4384d0" , "latest")    ,
    ("osg-23-upcoming-el9-release"      , "92897c00" , "non-latest"),
    ("osg-23-upcoming-el9-testing"      , "92897c00" , "non-latest"),
    ("osg-24-contrib-el8"               , "effc3be6" , "latest")    ,
    ("osg-24-empty-el8"                 , "effc3be6" , "latest")    ,
    ("osg-24-contrib-el9"               , "effc3be6" , "latest")    ,
    ("osg-24-empty-el9"                 , "effc3be6" , "latest")    ,
    ("osg-24-contrib-el10"              , "effc3be6" , "latest")    ,
    ("osg-24-empty-el10"                , "effc3be6" , "latest")    ,
    ("osg-24-internal-el8-development"  , "34e958b3" , "latest")    ,
    ("osg-24-internal-el8-release"      , "effc3be6" , "non-latest"),
    ("osg-24-internal-el9-development"  , "34e958b3" , "latest")    ,
    ("osg-24-internal-el9-release"      , "effc3be6" , "non-latest"),
    ("osg-24-internal-el10-development" , "34e958b3" , "latest")    ,
    ("osg-24-internal-el10-release"     , "effc3be6" , "non-latest"),
    ("osg-24-main-el8-development"      , "34e958b3" , "latest")    ,
    ("osg-24-main-el8-release"          , "effc3be6" , "non-latest"),
    ("osg-24-main-el8-testing"          , "effc3be6" , "non-latest"),
    ("osg-24-main-el9-development"      , "34e958b3" , "latest")    ,
    ("osg-24-main-el9-release"          , "effc3be6" , "non-latest"),
    ("osg-24-main-el9-testing"          , "effc3be6" , "non-latest"),
    ("osg-24-main-el10-development"     , "34e958b3" , "latest")    ,
    ("osg-24-main-el10-release"         , "effc3be6" , "non-latest"),
    ("osg-24-main-el10-testing"         , "effc3be6" , "non-latest"),
    ("osg-24-upcoming-el8-development"  , "34e958b3" , "latest")    ,
    ("osg-24-upcoming-el8-release"      , "effc3be6" , "non-latest"),
    ("osg-24-upcoming-el8-testing"      , "effc3be6" , "non-latest"),
    ("osg-24-upcoming-el9-development"  , "34e958b3" , "latest")    ,
    ("osg-24-upcoming-el9-release"      , "effc3be6" , "non-latest"),
    ("osg-24-upcoming-el9-testing"      , "effc3be6" , "non-latest"),
    ("osg-24-upcoming-el10-development" , "34e958b3" , "latest")    ,
    ("osg-24-upcoming-el10-release"     , "effc3be6" , "non-latest"),
    ("osg-24-upcoming-el10-testing"     , "effc3be6" , "non-latest"),
    ("osg-25-contrib-el8"               , "d4e9b1fc" , "non-latest"),
    ("osg-25-contrib-el9"               , "d4e9b1fc" , "non-latest"),
    ("osg-25-contrib-el10"              , "d4e9b1fc" , "non-latest"),
    ("osg-25-empty-el8"                 , "d4e9b1fc" , "non-latest"),
    ("osg-25-empty-el9"                 , "d4e9b1fc" , "non-latest"),
    ("osg-25-empty-el10"                , "d4e9b1fc" , "non-latest"),
    ("osg-25-internal-el8-development"  , "222c5d49" , "latest")    ,
    ("osg-25-internal-el8-release"      , "d4e9b1fc" , "non-latest"),
    ("osg-25-internal-el9-development"  , "222c5d49" , "latest")    ,
    ("osg-25-internal-el9-release"      , "d4e9b1fc" , "non-latest"),
    ("osg-25-internal-el10-development" , "222c5d49" , "latest")    ,
    ("osg-25-internal-el10-release"     , "d4e9b1fc" , "non-latest"),
    ("osg-25-main-el8-development"      , "222c5d49" , "latest")    ,
    ("osg-25-main-el8-release"          , "d4e9b1fc" , "non-latest"),
    ("osg-25-main-el8-testing"          , "d4e9b1fc" , "non-latest"),
    ("osg-25-main-el9-development"      , "222c5d49" , "latest")    ,
    ("osg-25-main-el9-release"          , "d4e9b1fc" , "non-latest"),
    ("osg-25-main-el9-testing"          , "d4e9b1fc" , "non-latest"),
    ("osg-25-main-el10-development"     , "222c5d49" , "latest")    ,
    ("osg-25-main-el10-release"         , "d4e9b1fc" , "non-latest"),
    ("osg-25-main-el10-testing"         , "d4e9b1fc" , "non-latest"),
    ("osg-25-upcoming-el8-development"  , "222c5d49" , "latest")    ,
    ("osg-25-upcoming-el8-release"      , "d4e9b1fc" , "non-latest"),
    ("osg-25-upcoming-el8-testing"      , "d4e9b1fc" , "non-latest"),
    ("osg-25-upcoming-el9-development"  , "222c5d49" , "latest")    ,
    ("osg-25-upcoming-el9-release"      , "d4e9b1fc" , "non-latest"),
    ("osg-25-upcoming-el9-testing"      , "d4e9b1fc" , "non-latest"),
    ("osg-25-upcoming-el10-development" , "222c5d49" , "latest")    ,
    ("osg-25-upcoming-el10-release"     , "d4e9b1fc" , "non-latest"),
    ("osg-25-upcoming-el10-testing"     , "d4e9b1fc" , "non-latest"),
]
# fmt: on


if __name__ == "__main__":
    sys.exit(main())
