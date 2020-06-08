#!/usr/bin/python

from __future__ import print_function

import json
import sys
import os


# python2/3 compat unicode handling

_unicode = type(u'')
if str is _unicode:
    def udec(obj):
        return obj

    def uopen(path, *a):
        return open(path, *a, encoding='utf-8')
else:
    def udec(obj):
        if isinstance(obj, _unicode):
            return obj.encode('utf-8')
        else:
            return obj

    def uopen(path, *a):
        return open(path, *a)

def do_subdir(name, items):
        os.mkdir(name)
        os.chdir(name)
        for k,v in items:
            write_json_fs_obj(v, str(k))
        os.chdir("..")


def write_json_fs_obj(obj, name):
    if isinstance(obj, list):
        do_subdir(name, enumerate(obj))
    elif isinstance(obj, dict):
        do_subdir(name, obj.items())
    else:
        with uopen(name, "w") as w:
            print(udec(obj), file=w)


def main(args):
    if (len(args) == 0 or len(args) > 2
        or args[0].startswith("-h") or args[0].startswith("--h")
    ):
        usage()
    path = args[0]
    dest = args[1] if len(args) == 2 else path + '%'
    fh = uopen(path) if path != '-' else sys.stdin
    write_json_fs_obj(json.load(fh), dest)


def usage():
    s = os.path.basename(__file__)
    print("Usage: {script} file.json [dest]".format(script=s))
    print()
    print("Expands contents of json file to new path 'dest'.")
    print("If file.json is '-', read from stdin.")
    print()
    print("If 'dest' path is omitted, 'file.json%'")
    print()
    sys.exit(0)


if __name__ == '__main__':
    main(sys.argv[1:])

