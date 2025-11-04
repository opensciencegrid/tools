#!/usr/bin/python3

"""
  Requires cracklib be installed as well as the
  cracklib python module ( https://pypi.python.org/pypi/cracklib );
  On CentOS 7, you can do this:
  sudo yum install python3-pip python3-devel cracklib-devel
  sudo pip3 install cracklib
"""
from __future__ import print_function

import crypt
import getpass
import random
import string
import cracklib


def main():
    password = getpass.getpass("Enter your new password: ")
    try:
        cracklib.VeryFascistCheck(password)
    except ValueError as err:
        print("Error: " + err.args[0])
        exit()
    verify = getpass.getpass("Enter your password again: ")
    if password != verify:
        print('Passwords do NOT match!')
        exit()
    salt = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
    print(crypt.crypt(password, "$6$rounds=656000$" + salt + "$"))


if __name__ == '__main__':
	main()
