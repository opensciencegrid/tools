#!/bin/bash

# This script is kept at https://vdt.cs.wisc.edu/svn/software/tools/osg-koji-offsite-backup

# Script to back up to a remote location the important directories in the OSG's
# Koji infrastructure. Should be run on host-3.
# I get around the "what if today's backups aren't done yet" problem by sending
# yesterday's backups instead. Should be fine since we run this once a week.

# Set these:
readonly REMOTE_LOGIN=osgsoftware
readonly REMOTE_HOST=backup.grid.iu.edu
readonly REMOTE_BASE_PATH=/usr/local/backup/osgsoftware
readonly LOCAL_BACKUP_ROOT=/export/backup
readonly KOJIHOST=koji-hub.batlab.org
readonly DBHOST=db-01.batlab.org
readonly RETRIES=10
readonly RETRY_WAIT=60
readonly KEY=/root/osg_backup_key
# TODO change this
readonly NOTIFY_EMAILS=(matyas@cs.wisc.edu)

################################################################################
DO_EMAIL=true
(( ${#NOTIFY_EMAILS[@]} > 0 )) || DO_EMAIL=false

send_email () {
    local subject="$1"
    $DO_EMAIL && mail -s "$subject" -r "$USER@$HOSTNAME" "${NOTIFY_EMAILS[@]}"
}

die () {
    echo "$@" >&2
    if $DO_EMAIL; then
        local emailfile="$(mktemp)"
        local subject="$(basename "$0") failed"
        echo "Offsite backups from $(hostname) to ${REMOTE_HOST} failed with the following error message:" >> "$emailfile"
        echo "$@" >> "$emailfile"
        if [[ -f $LOG ]]; then
            echo "Logs follow:"
            cat "$LOG" >> "$emailfile"
        fi
        send_email "$subject" < "$emailfile"
        rm -f "$emailfile"
    fi
    exit 1
}

require_var () {
    local var="${1?Usage: require_var VAR}"
    eval "[[ -n \${$var-} ]]" || die "$var not specified"
}

rsync_with_retry_or_die () {
    local src_path="$1"; shift
    local remote_path="$1"; shift
    # Remaining arguments are used as --link-dests

    local -a ssh_opts
    ssh_opts=(-i $KEY `#-o ServerAliveInterval=20`)
    local -a rsync_opts
    rsync_opts=(-rzq `#--partial` `#--partial-dir=.rsync-partial` -e "${ssh_opts[*]}")
    while [[ -n ${1-} ]]; do
        rsync_opts+=(--link-dest="$1")
        shift
    done

    local dest_path="$REMOTE_LOGIN@$REMOTE_HOST:$remote_path"
    local count=0
    while true; do
        rsync "${rsync_opts[@]}" "$src_path" "$dest_path" && \
            return 0
        if (( count >= RETRIES )); then
            die "Hit max retries while rsyncing $src_path to $dest_path; giving up"
        else
            (( count++ ))
            sleep $RETRY_WAIT
        fi
    done
}

compress_or_die () {
    local archive="$1"; shift

    tar -czpf "$archive" "$@" || \
        die "Error compressing $@ -> $archive"
}

################################################################################
set -o nounset

start_time=$(date +%s)
# Sanity check
require_var REMOTE_LOGIN
require_var REMOTE_HOST
require_var REMOTE_BASE_PATH
require_var LOCAL_BACKUP_ROOT
require_var KOJIHOST
require_var DBHOST
require_var RETRIES
require_var RETRY_WAIT

LOG="$(mktemp)"
TEMPDIR=$(mktemp -d)
trap "rm -f \"$LOG\"; rm -rf \"$TEMPDIR\"" EXIT
exec > "$LOG" 2>&1

backup_date=$(date +%F -d 'yesterday')
last_backup_date=$(date +%F -d '8 days ago')
workdir=$TEMPDIR/$backup_date
yesterdays_backups=$LOCAL_BACKUP_ROOT/$backup_date
remote_path=$REMOTE_BASE_PATH/$backup_date
remote_link_path=$REMOTE_BASE_PATH/$last_backup_date

# Moving the backups back a day so link one day before $last_backup_date too
alt_last_backup_date=$(date +%F -d '9 days ago')
alt_remote_link_path=$REMOTE_BASE_PATH/$alt_last_backup_date

cd "$yesterdays_backups"
mkdir -p "$workdir"
compress_or_die "$workdir/etc.tar.gz"           "$KOJIHOST/rootfs/etc"
compress_or_die "$workdir/roothome.tar.gz"      "$KOJIHOST/rootfs/root"
compress_or_die "$workdir/pgsql.tar.gz"         "$DBHOST/rootfs/var/lib/pgsql"
compress_or_die "$workdir/pgsql-backup.tar.gz"  "$DBHOST/rootfs/var/lib/pgsql-backup"
[[ -d $KOJIHOST/kojifs/packages ]] || die "$KOJIHOST/kojifs/packages not a directory"

trap "echo Interrupted; exit 3;" SIGINT SIGTERM
rsync_with_retry_or_die "$workdir/"                   "$remote_path"
rsync_with_retry_or_die "$KOJIHOST/kojifs/packages/"  "$remote_path/packages" \
    "$remote_link_path/packages" \
    "$alt_remote_link_path/packages"

end_time=$(date +%s)
(( duration = (end_time - start_time) ))
(( hours = (duration / 3600) ))
(( minutes = ( (duration % 3600) / 60 ) ))
(( seconds = (duration % 60) ))

printf "Koji offsite backups completed in %d:%02d:%02d\n" hours minutes seconds | \
    send_email "$(basename "$0") - success"


