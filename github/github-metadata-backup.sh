#!/bin/bash
set -e

topdir=/p/condor/workspaces/vdt/git
ghmdir=$topdir/github_meta
logdir=$topdir/log
srcdir=$topdir/script
local_ghmdir=$HOME/github_meta

# due to the enormous number of files involved:
#   - origin bare repo on AFS is $ghmdir/repos.git
#   - working copy is on local disk under $local_ghmdir

# Note:
#   - pyjwt and PyGithub libs installed locally on moria under ~/.local/lib
#   - See ~/git/ for the versions installed, with: ./setup.py build;
#                                                  ./setup.py install --user

cd "$local_ghmdir"

/usr/bin/stdbuf -oL \
$srcdir/ghb.py opensciencegrid $ghmdir/token >$logdir/ghmeta_backup.log \
                                            2>$logdir/ghmeta_backup.err

cd repos/
[[ -d .git ]] || git init
git add .
if [[ $(git status --porcelain) ]]; then
  git commit -qm auto-bak
  git push
fi

