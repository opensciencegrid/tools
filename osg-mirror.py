#!/usr/bin/env python
import logging
import pwd
import os
from os.path import join as opj
from socket import getfqdn
import shutil
import subprocess
import sys
import time as time_
from time import clock, ctime, sleep, time



REPOS_ROOT = "/p/vdt/public/html/repos/3.0/el5"
#REPOS_ROOT = "/scratch/matyas/repos/3.0/el5"
GOC_ROOT = "rsync://repo.grid.iu.edu"
LOCK_RETRY_MAX = 60 * 30

# REPO_MAP: [rsync from, rsync to] pairs
REPO_MAP = {
    'development': [opj(GOC_ROOT, "osg-development"), opj(REPOS_ROOT, "development")],
    'testing': [opj(GOC_ROOT, "osg-testing"), opj(REPOS_ROOT, "testing")],
    'production': [opj(GOC_ROOT, "osg-release"), opj(REPOS_ROOT, "production")],
    'contrib': [opj(GOC_ROOT, "osg-contrib"), opj(REPOS_ROOT, "contrib")],
}

def safe_makedirs(directory, mode=0777):
    """A wrapper around os.makedirs that does not raise an exception if the
    directory already exists.
    
    """
    if not os.path.isdir(directory):
        os.makedirs(directory, mode)


def obtain_lock(lock_file):
    """Check for a lock on the repository, and obtain it if the repo is unlocked."""
    #   Check for lockfile. Lockfiles should be in AFS and should contain the
    # hostname, the uid, and the pid of the process.
    logging.debug("Obtaining lock %s", lock_file)
    retry = 60
    while retry < LOCK_RETRY_MAX and os.path.exists(lock_file):
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
                    logging.info("Lockfile exists and owned by running "
                                 "process. Retrying in %d seconds." % retry)
                    sleep(retry)
                    retry *= 2
                    continue
                else:
                    logging.warning("Removing stale lockfile " + lock_file)
                    os.unlink(lock_file)
                    break
            else:
                logging.info("Lockfile exists and owned by process on "
                             "remote machine. Retrying in %d seconds." % retry)
                sleep(retry)
                retry *= 2
                continue
        finally:
            fh.close()
    if retry >= LOCK_RETRY_MAX:
        if not their_user or not their_fqdn or not their_pid:
            raise Exception("Lockfile " + lock_file + " exists but its contents"
                            " are not recognized.")
        else:
            raise Exception("Lockfile " + lock_file + " exists.\n"
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
    logging.debug("Releasing lock %s", lock_file)
    if os.path.exists(lock_file):
        os.unlink(lock_file)


def do_mirror(goc_repo, live_repo, ip_repo, old_repo):
    if os.path.exists(ip_repo):
        shutil.rmtree(ip_repo)

    rsync_proc = subprocess.Popen(
        ["/usr/bin/rsync", "-art", goc_repo, "--exclude=debug/", ip_repo],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    rsync_outerr = rsync_proc.communicate()[0]
    rsync_ret = rsync_proc.returncode

    if rsync_ret:
        logging.error(rsync_outerr)
        raise Exception("Rsync had problems!")
    else:
        logging.debug("Rsync succeeded, output:\n%s", rsync_outerr)

    if os.path.exists(live_repo):
        logging.debug("Saving live repository %s to %s", live_repo, old_repo)
        shutil.move(live_repo, old_repo)

    logging.debug("Making in-progress repository %s live", ip_repo)
    shutil.move(ip_repo, live_repo)

    if os.path.exists(old_repo):
        logging.debug("Removing old repo %s", old_repo)
        shutil.rmtree(old_repo)

    

    
    

#
# SCRIPT BEGINS HERE
#

logging.basicConfig(format="%(levelname)s:" + os.path.basename(sys.argv[0]) + ":%(message)s",
                    level=logging.DEBUG)

if len(sys.argv) < 2:
    print >>sys.stderr, ("Usage: %s REPO..." % sys.argv[0])
    print >>sys.stderr, ("Valid repositories are: " +
                         ",".join(REPO_MAP.keys()))
    sys.exit(2)

# validate arguments
for a in sys.argv[1:]:
    if a not in REPO_MAP.keys():
        print >>sys.stderr, ("%s is not a valid repository name. Valid "
                             "repositories are: %s" % (a, ",".join(REPO_MAP.keys())))
        sys.exit(2)

for repository in sys.argv[1:]:
    goc_repo = REPO_MAP[repository][0]
    live_repo = REPO_MAP[repository][1]
    logging.debug("*** Updating repository %s via rsync from %s to %s ***\n\n" %
                  (repository, goc_repo, live_repo))
    repo_parent = os.path.dirname(live_repo)
    repo_bn = os.path.basename(live_repo)
    ip_repo = opj(repo_parent, ".in_progress." + repo_bn)
    old_repo = opj(repo_parent, ".old." + repo_bn)
    lock_file = opj(repo_parent, ".lock." + repo_bn)

    if os.path.exists(old_repo):
        logging.debug("Removing old repo %s", old_repo)
        shutil.rmtree(old_repo)

    obtain_lock(lock_file)
    try:
        start_time = time()
        logging.debug("Started at " + ctime())
        do_mirror(goc_repo, live_repo, ip_repo, old_repo)
        end_time = time()
        logging.debug("Finished at " + ctime())
        elapsed_time = end_time - start_time
        logging.debug("Elapsed time: %f seconds", elapsed_time)
    finally:
        release_lock(lock_file)


