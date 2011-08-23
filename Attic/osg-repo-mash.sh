#!/bin/bash

die() {
    echo "Fatal Error: $@" 1>&2
    rm -f $LOCK
    exit 1
}

if [[ $# -lt 1 ]]; then
    die "Repository not given. Repository should be either 'development' or 'testing'"
fi

export REPOSITORY=${1}
export MASH_LOCATION=/p/vdt/workspace/mash/mash-0.5.20
export REPOS_ROOT=/p/vdt/public/html/repos
export LIVE_REPO=$REPOS_ROOT/3.0/el5/$REPOSITORY
export IP_REPO=$REPOS_ROOT/.inprogress.$REPOSITORY
export OLD_REPO=$REPOS_ROOT/.old.$REPOSITORY
export MASH_CONFIG=/p/vdt/workspace/mash/etc/mash_osg.conf
if [[ ! -e "$MASH_CONFIG" ]]; then
    die "Mash config file $MASH_CONFIG not found"
fi
export MASH_CACHE=$(grep 'cachedir' $MASH_CONFIG | sed -e 's/^.*=\s*//g')

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
/usr/bin/python $MASH_LOCATION/mash.py $REPOSITORY -c $MASH_CONFIG -o $IP_REPO | grep -v 'not signed'

result=$?

if [[ $result == 0 ]]; then
    # Swap out the repos
    if [[ ! -e "$IP_REPO/$REPOSITORY" ]]; then
        die "Mash returned 0 but updated repo not found at $IP_REPO/$REPOSITORY"
    fi
    if [[ -e "$LIVE_REPO" ]]; then
        echo "Saving live repository $LIVE_REPO to $OLD_REPO"
        mv "$LIVE_REPO" "$OLD_REPO" || die "Unable to save live repository $LIVE_REPO to $OLD_REPO"
    fi
    echo "Making in-progress repository $IP_REPO/$REPOSITORY live"
    mkdir -p $(dirname "$LIVE_REPO")
    mv "$IP_REPO/$REPOSITORY" "$LIVE_REPO" || die "Unable to make in-progress repository at $IP_REPO/$REPOSITORY live"
    echo "Removing old repo $OLD_REPO"
    rm -rf "$OLD_REPO"
    echo "Removing in-progress repo $IP_REPO"
    rm -rf "$IP_REPO"

    echo "Removing cache $MASH_CACHE"
    rm -rf "$MASH_CACHE"
else
    die "Mash returned $result"
fi

rm -f $LOCK

