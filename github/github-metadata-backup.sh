#!/bin/bash

topdir=/p/condor/workspaces/vdt/git
ghmdir=$topdir/github_meta
logdir=$topdir/log
srcdir=$topdir/script

# PyGithub and pyjwt libs installed locally on ingwe
export PYTHONPATH=$HOME/.local_python/lib/python2.6/site-packages/

cd $ghmdir

/usr/bin/stdbuf -oL \
$srcdir/ghb.py opensciencegrid $ghmdir/token >$logdir/ghmeta_backup.log \
                                            2>$logdir/ghmeta_backup.err

cd repos/
[[ -d .git ]] || git init
git add .
git commit -qm auto-bak
