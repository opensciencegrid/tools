#!/bin/bash
set -e

today=$(date +%F)
weekday=$(date +%a)
yesterday=$(date -d yesterday +%F)
lastweek=$(date -d '1 week ago' +%F)

datadir=$HOME/ce_xml_data
logdir=$HOME/ce_xml_logs

FROM=osg-ce-diff@chtc.wisc.edu
REPLYTO=edquist@cs.wisc.edu
TO=(
    lmichael@wisc.edu,
    edquist@cs.wisc.edu
)

[[ -d $datadir ]] || mkdir "$datadir"
[[ -d $logdir  ]] || mkdir "$logdir"

PATH=$(dirname "$0"):$PATH

do_email_report () {
  prev=$1
  subject_prefix=$2
  added_report=$datadir/ces_added.$today.$prev.txt
  if [[ ! -e "$datadir"/ce_resources.$prev.xml ]]; then
    return
  fi
  topo-ces.py "$datadir"/ce_resources.{$prev,$today}.xml > "$added_report"

  if [[ -s $added_report ]]; then
    send_email "$subject_prefix"
  fi
}

send_email () {
  {
  {
    echo "From: $FROM"
    echo "Reply-To: $REPLYTO"
    echo "To: ${TO[*]}"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/plain"
    echo "Subject: ${*}CEs added between $prev and $today"
    echo
    echo "CEs added between $prev and $today:"
    echo
    cat "$added_report"
  } | /usr/sbin/sendmail -t
  } </dev/null &>"$logdir/emailer.$today.$prev.log" &
}


topo-ces.py --getxml > "$datadir/ce_resources.$today.xml"

do_email_report "$yesterday"

if [[ $weekday = Mon ]]; then
  do_email_report "$lastweek" "Weekly summary - "
fi

