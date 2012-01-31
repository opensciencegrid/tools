#!/usr/bin/env python
import logging
import pwd
import os
from os.path import join as opj
from socket import getfqdn
import shutil
import signal
import subprocess
import sys
from time import clock, ctime, sleep, time



#REPOS_ROOT = "/p/vdt/public/html/repos"
REPOS_ROOT = "/scratch/matyas/repos"
GOC_ROOT = "rsync://repo.grid.iu.edu"
ITB_ROOT = "rsync://repo-itb.grid.iu.edu/osg"
LOCK_RETRY_MAX = 60 * 20
GLOBAL_TIMEOUT = 60 * 119 # 2 hours

DEBUG = True

REPO_MAP = {}
vdtver = "3.0"
for distro in ['el5', 'el6']:
    for level in ['development', 'contrib', 'testing', 'release']:
        key = "%(vdtver)s-%(distro)s-%(level)s" % locals()
        from_loc = opj(ITB_ROOT, vdtver, distro, "osg-%s/" % level)
        if level == 'release':
            locallevel = 'production'
        else:
            locallevel = level
        to_loc = opj(REPOS_ROOT, vdtver, distro, locallevel)
        REPO_MAP[key] = [from_loc, to_loc]

class Alarm(Exception): pass
class RsyncFailure(Exception): pass

def alarm_handler(signum, frame):
    if signum == signal.SIGALRM:
        raise Alarm()
    

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
        fh = open(lock_file, 'r')
        try:
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
            if fh:
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
    safe_makedirs(os.path.dirname(lock_file))
    fh = open(lock_file, 'w')
    try:
        lock_contents = ":".join([pwd.getpwuid(os.getuid())[0],
                                  getfqdn(),
                                  str(os.getpid())])
        logging.debug("Lock contents: %s", lock_contents)
        print >> fh, lock_contents
    finally:
        if fh:
            fh.close()


def release_lock(lock_file):
    """Release the lock (if there is one)"""
    logging.debug("Releasing lock %s", lock_file)
    if os.path.exists(lock_file):
        os.unlink(lock_file)


def do_mirror(goc_repo, live_repo, ip_repo, old_repo):
    if os.path.exists(ip_repo):
        shutil.rmtree(ip_repo)

    rsync_cmd = ["/usr/bin/rsync", "-arvt", goc_repo, "--exclude=debug/", ip_repo]
    if os.path.exists(live_repo):
        logging.debug("Live repo exists. Passing --copy-dest=%s to rsync", live_repo)
        rsync_cmd += ["--copy-dest=" + live_repo]

    rsync_outerr = ""
    try:
        rsync_proc = subprocess.Popen(
            rsync_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

        # communicate() returns nothing if we kill the process via a signal,
        # but we still want the output, so we're not using it.
        while rsync_proc.poll() is None:
            rsync_outerr += rsync_proc.stdout.readline()
        rsync_ret = rsync_proc.returncode
    except Alarm:
        logging.critical("Global timeout exceeded")
        logging.critical("Last rsync command: " + str(rsync_cmd))
        logging.critical("rsync output follows:\n%s", rsync_outerr)
        rsync_proc.send_signal(signal.SIGALRM)
        raise

    if rsync_ret:
        logging.error("Last rsync command: " + str(rsync_cmd))
        logging.error(rsync_outerr)
        logging.error("Died with code %d", rsync_ret)
        raise RsyncFailure("rsync had problems!")
    else:
        logging.debug("rsync succeeded, output:\n%s", rsync_outerr)

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

if DEBUG:
    level = logging.DEBUG
else:
    level = logging.WARNING

logging.basicConfig(format="%(levelname)s:" + os.path.basename(sys.argv[0]) + ":%(message)s",
                    level=level)

if len(sys.argv) < 2:
    print >> sys.stderr, ("Usage: %s REPO..." % sys.argv[0])
    print >> sys.stderr, ("Valid repositories are: ALL," +
                          ",".join(REPO_MAP.keys()))
    sys.exit(2)

# validate arguments
if 'ALL' not in sys.argv:
    for a in sys.argv[1:]:
        if a not in REPO_MAP:
            print >> sys.stderr, ("%s is not a valid repository name. Valid "
                                  "repositories are: ALL,%s" %
                                  (a, ",".join(REPO_MAP.keys())))
            sys.exit(2)
    repos_to_sync = sys.argv[1:]
else:
    repos_to_sync = REPO_MAP.keys()

logging.debug("Setting alarm for %d minutes", (GLOBAL_TIMEOUT / 60))
signal.signal(signal.SIGALRM, alarm_handler)
signal.alarm(GLOBAL_TIMEOUT)

for repository in repos_to_sync:
    goc_repo, live_repo = REPO_MAP[repository]
    logging.debug("*** Updating repository %s via rsync ***"
                  "\nfrom: %s\nto  : %s\n\n" %
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
    except Alarm:
        sys.exit(14)
    except RsyncFailure:
        # in case of rsync failure, try the next repository instead of aborting
        # everything
        continue


