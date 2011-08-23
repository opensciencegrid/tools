#!/usr/bin/env python
import glob
import logging
import pwd
import re
import os
from socket import getfqdn
import shutil
import subprocess
import sys
import time as time_
from time import clock, ctime, sleep, time
import traceback


VALID_REPOS = ["development", "testing"]
MASH_LOCATION = "/p/vdt/workspace/mash/mash-0.5.20"
# TODO: Install our patched koji-1.6.0 and change this.
KOJI_LOCATION = "/p/vdt/workspace/mash/koji-1.4.0"
REPOS_ROOT = "/p/vdt/public/html/repos"
#REPOS_ROOT = "/scratch/matyas/repos"
MASH_CONFIG = "/p/vdt/workspace/mash/etc/mash_osg.conf"
RETRY_MAX = 60 * 30


class Error(Exception):
    """Class for expected exceptions. No traceback unless debugging."""
    pass


def safe_makedirs(directory, mode=0777):
    """A wrapper around os.makedirs that does not raise an exception if the
    directory already exists.
    
    """
    if not os.path.isdir(directory):
        os.makedirs(directory, mode)


def get_mash_cache():
    """Find out where the mash cache is by reading the mash config file."""
    if not os.path.exists(MASH_CONFIG):
        raise Error("Mash config file " + MASH_CONFIG + " not found!")
    #   Get mash_cache by parsing MASH_CONFIG
    try:
        fh = open(MASH_CONFIG, 'r')
        for line in fh:
            line = line.strip()
            match = re.match(r'cachedir\s*=\s*(.*)$', line)
            if match:
                mash_cache = match.group(1)
                break
        if not match:
            raise Error("Could not find cachedir in mash config file " +
                        MASH_CONFIG)
    finally:
        fh.close()

    return mash_cache


def obtain_lock(lock_file):
    """Check for a lock on the repository, and obtain it if the repo is unlocked."""
    #   Check for lockfile. Lockfiles should be in AFS and should contain the
    # hostname, the uid, and the pid of the process.
    retry = 60
    while retry < RETRY_MAX and os.path.exists(lock_file):
        #   If on local machine, see if that pid still exists. If not, continue.
        try:
            fh = open(lock_file, 'r')
            line = fh.readline().strip()
            try:
                their_user, their_fqdn, their_pid = line.split(":")
            except ValueError:
                logging.warning("Unrecognized lockfile. Retrying in %d seconds." % retry)
                sleep(retry)
                retry *= 2
                continue
            if their_fqdn == getfqdn():
                if os.path.exists(os.path.join("/proc", their_pid)):
                    logging.info("Lockfile exists and owned by running " +
                                 "process. Retrying in %d seconds." % retry)
                    sleep(retry)
                    retry *= 2
                    continue
                else:
                    logging.warning("Removing stale lockfile " + lock_file)
                    os.unlink(lock_file)
                    break
            else:
                logging.info("Lockfile exists and owned by process on " +
                             "remote machine. Retrying in %d seconds." % retry)
                sleep(retry)
                retry *= 2
                continue
        finally:
            fh.close()
    if retry >= RETRY_MAX:
        if not their_user or not their_fqdn or not their_pid:
            raise Error("Lockfile " + lock_file + " exists but its contents" +
                        " are not recognized.")
        else:
            raise Error("Lockfile " + lock_file + " exists.\n" +
                        "Lock created by " + their_user + " on " +
                        their_fqdn + " with pid " + str(their_pid))
    #   Create our lockfile.
    try:
        fh = open(lock_file, 'w')
        lock_contents = ":".join([pwd.getpwuid(os.getuid())[0],
                                  getfqdn(),
                                  str(os.getpid())])
        logging.debug("Lock contents: %s", lock_contents)
        print >>fh, lock_contents
    finally:
        fh.close()


def release_lock(lock_file):
    """Release the lock (if there is one)"""
    if os.path.exists(lock_file):
        os.unlink(lock_file)

def do_update():
    if os.path.exists(ip_repo):
        shutil.rmtree(ip_repo)

    # Mash needs the proper PYTHONPATH set.
    mash_environ = os.environ.copy()
    mash_environ['PYTHONPATH'] = (KOJI_LOCATION + ":" +
                                  os.path.join(MASH_LOCATION, "mash"))
    mash_proc = subprocess.Popen(
        ["/usr/bin/python", os.path.join(MASH_LOCATION, "mash.py"), repository,
         "-c", MASH_CONFIG, "-o", ip_repo],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        env=mash_environ)
    mash_outerr = mash_proc.communicate()[0]
    mash_ret = mash_proc.returncode

    if mash_ret or re.search("mash failed", mash_outerr):
        logging.error(mash_outerr)
        raise Error("Mash failed!")
    elif not os.path.exists(ip_repo_subdir):
        raise Error("Mash claims success, but updated repo not found at " +
                    ip_repo_subdir)
    else:
        logging.debug("Mash succeeded, output:\n%s", mash_outerr)


    if os.path.exists(live_repo):
        logging.debug("Saving live repository %s to %s", live_repo, old_repo)
        shutil.move(live_repo, old_repo)

    logging.debug("Making in-progress repository %s live",
                  ip_repo_subdir)
    safe_makedirs(os.path.dirname(live_repo))
    shutil.move(ip_repo_subdir, live_repo)

    if os.path.exists(old_repo):
        logging.debug("Removing old repo %s", old_repo)
        shutil.rmtree(old_repo)

    if os.path.exists(ip_repo):
        logging.debug("Removing in-progress repo %s", ip_repo)
        shutil.rmtree(ip_repo)

    #   If no other lock files but our own exist, nuke $mash_cache
    all_locks = glob.glob(lock_glob)
    if len(all_locks) == 1 and all_locks[0] == lock_file:
        logging.debug("Removing cache %s", mash_cache)
        shutil.rmtree(mash_cache)




#
# SCRIPT BEGINS HERE
#

# TODO: Make configurable.
logging.basicConfig(format="%(levelname)s:" + os.path.basename(sys.argv[0]) + ":%(message)s",
                    level=logging.DEBUG)

if len(sys.argv) < 2 or sys.argv[1] not in VALID_REPOS:
    print >>sys.stderr, "Valid repository not given. Valid repositories are: " + ",".join(VALID_REPOS)
    sys.exit(2)

repository = sys.argv[1]
live_repo = os.path.join(REPOS_ROOT, "3.0/el5", repository)
ip_repo = os.path.join(REPOS_ROOT, ".inprogress." + repository)
ip_repo_subdir = os.path.join(ip_repo, repository)
old_repo = os.path.join(REPOS_ROOT, ".old." + repository)
lock_file = os.path.join(REPOS_ROOT, ".lock." + repository)
lock_glob = os.path.join(REPOS_ROOT, ".lock.*")
try:
    mash_cache = get_mash_cache()
    logging.debug("Mash cache is %s", mash_cache)

    if not os.path.exists(REPOS_ROOT):
        raise Error("Repository root dir " + REPOS_ROOT + " doesn't exist!")

    logging.debug("Obtaining lock %s", lock_file)
    obtain_lock(lock_file)
    try:
        start_time = time()
        logging.debug("Started at " + ctime())
        do_update()
        end_time = time()
        logging.debug("Finished at " + ctime())
    finally:
        logging.debug("Releasing lock %s", lock_file)
        release_lock(lock_file)
    elapsed_time = end_time - start_time
    logging.debug("Elapsed time: %f seconds", elapsed_time)
except SystemExit, e:
    sys.exit(e.code)
except Error, e:
    logging.error("An error occurred: " + str(e))
    logging.debug(traceback.format_exc())
    sys.exit(1)
except Exception, e:
    logging.error("Unhandled exception: " + str(e))
    logging.error(traceback.format_exc())
    sys.exit(3)

