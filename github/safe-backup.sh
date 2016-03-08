#!/bin/bash

bakdir=/p/condor/workspaces/vdt/git

# list file of git clone urls, path can be absolute or relative to bakdir
git_remotes_listfile=remotes.list

email_from=cndrutil@cs.wisc.edu
email_to="edquist@cs.wisc.edu matyas+cron@cs.wisc.edu"

datelog () {
  echo "$(date): $*"
}

# initialize (if missing) and fetch current remote git url
safebakrepo () {
  ( # run in subshell that exits on errors
    set -e
    remote=${remote%/}
    repo=${remote##*/}
    [[ $repo = *.git ]] || repo+=.git
    if [[ -e $repo/NO_FETCH ]]; then
        datelog "Skipping $remote (NO_FETCH file present)"
        return
    fi

    [[ -d $repo ]] || initrepo

    datelog "Fetching $remote"
    cd "$repo"
    git fetch
    safetags
  )
}

# initialize new bare repo to mirror current remote git url
initrepo () {
  (
    datelog "Initializing backup repo for $remote"
    mkdir "$repo"
    cd "$repo"
    git init --bare
    git remote add origin "$remote"
    git config transfer.fsckObjects  true
    git config core.logAllRefUpdates true

    # allow non-ff pull request updates, and ff-only updates for all other refs
    git config remote.origin.fetch '+refs/pull/*:refs/pull/*'
    git config --add remote.origin.fetch 'refs/*:refs/*'
  )
}

# create reflog for all tags; detect tag updates
safetags () {
    for tag in $(git tag); do
        taglog=logs/refs/tags/$tag
        tagdir=${taglog%/*}
        [[ -d $tagdir ]] || mkdir -p $tagdir
        [[ -e $taglog ]] || touch $taglog
        if [[ -s $taglog ]]; then
            echo "Warning: tag '$tag' has a history..."
            git reflog refs/tags/$tag
            echo
            touch $tmpd/failures-detected
        fi
    done
}

email_errors () {
    { echo "Errors detected for backup run at $(date)."
      echo
      echo ---
      echo
      cat $tmpd/backups.log
    } | mailx -s "Git[Hub] Safe-Backup errors" -r "$email_from" $email_to
}

cd "$bakdir"
tmpd=$(mktemp -d)
trap 'rm -rf "$tmpd"' EXIT

{ # log all stdout/stderr from this section

# attempt to acquire lock before doing fetches
exec 99>> .backups.lk

if ! flock -n 99; then
    datelog 'Could not acquire lock (previous run still active) -' \
            'Please investigate!!!'
    touch $tmpd/failures-detected
else
    remotes=( $(grep '^[^#]' "$git_remotes_listfile") )

    for remote in "${remotes[@]}"; do
        safebakrepo
        [[ $? -eq 0 ]] || touch $tmpd/failures-detected
    done
fi
echo ---
} &>$tmpd/backups.log

cat $tmpd/backups.log >> backups.log

if [[ -e $tmpd/failures-detected ]]; then
    if [[ -t 1 ]]; then
        echo errors detected...
    fi
    # send error email if our last failure email was sent more than
    # a day ago, or if there was a successful run since then
    touch -d "$(date -d '1 day ago')" $tmpd/yesterday-mtime
    if [[ last-failure-email-mtime -ot $tmpd/yesterday-mtime ||
          last-failure-email-mtime -ot last-success-mtime    ]]; then
        email_errors 99>&-  # don't pass lock fd to mailer
        touch last-failure-email-mtime
    fi
    cp $tmpd/backups.log last-failure-msg
else
    touch last-success-mtime
fi

/usr/sbin/logrotate --state $bakdir/.logrotate.state $bakdir/backups.logrotate

