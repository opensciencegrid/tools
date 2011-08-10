#!/bin/bash

die() {
    echo "Fatal Error: $@" 1>&2
    rm -f $LOCK
    exit 1
}

export REPOSITORY=development
export MASH_LOCATION=/p/vdt/workspace/mash/mash-0.5.20
export REPOS_ROOT=/p/vdt/public/html/repos
export LIVE_REPO=$REPOS_ROOT/3.0/el5/$REPOSITORY
export IP_REPO=$REPOS_ROOT/.inprogress.$REPOSITORY
export OLD_REPO=$REPOS_ROOT/.old.$REPOSITORY
export LAST_REPO=$REPOS_ROOT/.last.$REPOSITORY

if [[ ! -d "$REPOS_ROOT" ]]; then
    die "Repository root directory $REPOS_ROOT doesn't exist!!!"
fi

# Not actually a real lock, just pretends to be one.
export LOCK=/tmp/mash_workdir2/$REPOSITORY.inprogress
if [[ -e $LOCK ]];
then
    echo Lock $LOCK exists. Someone may
    echo already be updating the repos.
    exit 0
fi
mkdir -p $(dirname $LOCK)
touch $LOCK

# Create the repository with mash.
export PYTHONPATH=/p/vdt/workspace/mash/koji-1.4.0:$MASH_LOCATION/mash
if [[ -e $IP_REPO ]]; then
    rm -rf $IP_REPO
fi
/usr/bin/python $MASH_LOCATION/mash.py $REPOSITORY -c /p/vdt/workspace/mash/etc/mash_osg.conf -o $IP_REPO

result=$?

if [[ $result == 0 ]]; then
    # Swap out the repos
    if [[ ! -e "$IP_REPO/$REPOSITORY" ]]; then
        die "Mash succeeded but updated repo not found at $IP_REPO/$REPOSITORY"
    fi
    if [[ -e "$LIVE_REPO" ]]; then
        echo "Saving live repository $LIVE_REPO to $OLD_REPO"
        mv "$LIVE_REPO" "$OLD_REPO" || die "Unable to save live repository $LIVE_REPO to $OLD_REPO"
    fi
    echo "Making in-progress repository $IP_REPO/$REPOSITORY live"
    mv "$IP_REPO/$REPOSITORY" "$LIVE_REPO" || die "Unable to make in-progress repository at $IP_REPO/$REPOSITORY live"
    # We don't have enough disk space to move OLD_REPO to LAST_REPO. Just nuke OLD_REPO for now.
    echo "Removing old repo $OLD_REPO"
    rm -rf "$OLD_REPO"
#    if [[ -e "$LAST_REPO" ]]; then
#        echo "Removing previous repo $LAST_REPO"
#        rm -rf "$LAST_REPO"
#    fi
#    if [[ -e "$OLD_REPO" ]]; then
#        echo "Preserving old repo $OLD_REPO at $LAST_REPO"       
#        mv "$OLD_REPO" "$LAST_REPO" || die "Unable to preserve old repo $OLD_REPO at $LAST_REPO"
#    fi
    echo "Removing in-progress repo $IP_REPO"
    rm -rf "$IP_REPO"
else
    die "Mash returned $result"
fi

rm -f $LOCK

