#!/usr/bin/env python2
# -*- coding: utf-8 -*-
"""
Update a repo stored in DIRECTORY with the "origin" upstream at REPO to
the latest, and check out the given BRANCH.

If DIRECTORY does not exist, REPO is cloned instead.

"""
from __future__ import print_function
from argparse import ArgumentParser
from email.mime.text import MIMEText
import logging
import logging.handlers
import pipes
import pwd
import os
import six
import smtplib
import socket
import subprocess
import sys

if six.PY2:
    from StringIO import StringIO
else:
    from io import StringIO


log = logging.getLogger(__name__)


def send_email(recipients, subject, text):
    msg = MIMEText(text)

    username = pwd.getpwuid(os.getuid()).pw_name
    hostname = socket.gethostname()

    msg["Subject"] = subject
    msg["To"] = ", ".join(recipients)
    msg["From"] = username + "@" + hostname

    smtp = smtplib.SMTP("localhost")
    smtp.sendmail(msg["From"], recipients, msg.as_string())
    smtp.quit()


def run_git_command(command, directory=None, git_directory=None):
    """Run an arbitrary git command, optionally specifying the git directory
    For a bare git repo, specify `git_directory` but not `directory`.

    Args:
        command (list of str) The git command to run
        directory (str)       path to git work-tree, if not current directory
        git_directory (str)   path to git-dir, if not .git subdirectory of work-tree

    Returns:
        bool: True if successful, False otherwise

    """
    base_command = ["git"]
    if directory:
        base_command += ["--work-tree", directory]
        if git_directory is None:
            git_directory = os.path.join(directory, ".git")
    if git_directory:
        base_command += ["--git-dir", git_directory]

    full_command = base_command + command

    git_proc = subprocess.Popen(
        full_command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    out = git_proc.communicate()[0].strip()
    outstr = "output:\n%s\n\n" % out if out else "no output\n"

    command_str = " ".join(pipes.quote(x) for x in full_command)
    if git_proc.returncode != 0:
        log.error("%s... FAILED  %s", command_str, outstr)
        return False

    log.debug("%s... ok  %s", command_str, outstr)
    return True


def git_clone_or_pull(repo, directory, branch):
    """Clone a git repository from `repo` into `directory`, or, if a git
    repository already exists, update to the latest changes from `origin`.
    Then, check out `branch`

    Returns:
        bool: True if all operations succeeded, False otherwise

    """
    if not os.path.exists(directory):
        log.info(
            "Making initial repo clone from %s to %s; using branch %s\n",
            repo,
            directory,
            branch,
        )
        ok = run_git_command(["clone", repo, directory])
        ok = ok and run_git_command(["checkout", branch], directory=directory)
        return ok

    if os.path.exists(os.path.join(directory, ".git")):
        log.info(
            "Cleaning and updating %s to the latest branch %s from origin\n",
            directory,
            branch,
        )
        _ = run_git_command(["clean", "-df"], directory=directory)
        ok = run_git_command(["fetch", "origin"], directory=directory)
        ok = ok and run_git_command(
            ["reset", "--hard", "origin/%s" % (branch)], directory=directory
        )
        return ok

    log.error(
        "%s already exists but is not a git repository; not touching it.", directory
    )
    return False


def main(argv):
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        "repo", metavar="URL", help="The URL of the Git repo to download from"
    )
    parser.add_argument(
        "directory", metavar="DIRECTORY", help="The directory to download to"
    )
    parser.add_argument(
        "branch",
        metavar="BRANCH",
        nargs="?",
        default="master",
        help="The Git branch to use (default %(default)s)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="count",
        default=0,
        help="Say more; can specify multiple times",
    )
    parser.add_argument(
        "--quiet",
        "-q",
        action="count",
        default=0,
        help="Say less; can specify multiple times",
    )
    parser.add_argument(
        "--notify",
        metavar="EMAIL",
        action="append",
        default=None,
        help="Email to notify in case of failure; can specify multiple times",
    )
    parser.add_argument(
        "--notify-on-success", action="store_true", help="Also send mail on success"
    )
    parser.add_argument(
        "--logfile", metavar="PATH", default=None, help="Path to logfile"
    )
    parser.add_argument(
        "--subject",
        default=argv[0],
        help="Subject to prefix notification email with; default: %(default)s",
    )
    args = parser.parse_args(argv[1:])

    # Set up logging for email: log temporarily into a string and send it at the
    # end of the script.
    logstream = StringIO()
    streamhandler = logging.StreamHandler(logstream)
    log.addHandler(streamhandler)

    # Set up logging for a file
    if args.logfile:
        filehandler = logging.handlers.RotatingFileHandler(
            args.logfile, maxBytes=10 << 20, backupCount=1
        )
        fileformatter = logging.Formatter("%(asctime)s %(levelname)-8s %(message)s")
        filehandler.setFormatter(fileformatter)
        log.addHandler(filehandler)

    # Set the log level
    loglevel = max(logging.DEBUG, logging.WARNING + 10 * (args.quiet - args.verbose))
    log.setLevel(loglevel)

    try:
        ret = 0 if git_clone_or_pull(args.repo, args.directory, args.branch) else 1
    except Exception as e:
        log.exception("Unhandled exception: %s", e)
        ret = 99

    if ret != 0:
        log.info("Update failed")
        if args.notify:
            send_email(args.notify, "%s: FAIL" % args.subject, logstream.getvalue())
    elif args.notify_on_success:
        log.info("Update succeeded")
        if args.notify:
            send_email(args.notify, "%s: ok" % args.subject, logstream.getvalue())

    return ret


if __name__ == "__main__":
    logging.basicConfig(format="%(message)s")
    sys.exit(main(sys.argv))
