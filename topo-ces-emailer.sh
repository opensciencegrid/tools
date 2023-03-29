#!/bin/bash
set -e

# crontab:  0 6 * * *   tools/topo-ces-emailer.sh

today=$(date +%F)
weekday=$(date +%a)
monthday=$(date +%d)
yesterday=$(date -d yesterday +%F)
lastweek=$(date -d '1 week ago' +%F)
lastmonth=$(date -d '1 month ago' +%F)

datadir=$HOME/ce_xml_data
logdir=$HOME/ce_xml_logs

FROM=osg-ce-diff@chtc.wisc.edu
REPLYTO=matyas@cs.wisc.edu
TO=(
    jstathas@morgridge.org,
    blin@cs.wisc.edu,
    fkw888@gmail.com,
    cat@cs.wisc.edu,
    jdost@ucsd.edu,
    matyas@cs.wisc.edu
)

[[ -d $datadir ]] || mkdir "$datadir"
[[ -d $logdir  ]] || mkdir "$logdir"

PATH=$(dirname "$0"):$PATH

do_email_report () {
  prev=$1
  subject_prefix=$2
  always_send=$3
  added_report=$datadir/ces_added.$today.$prev.txt
  if [[ ! -e "$datadir"/ce_resources.$prev.xml ]]; then
    return
  fi
  topo-ces.py "$datadir"/ce_resources.{$prev,$today}.xml > "$added_report"

  if [[ -s $added_report || $always_send = Y ]]; then
    send_email
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
    if [[ -s $added_report ]]; then
      echo "Subject: ${subject_prefix}CEs added between $prev and $today"
      echo
      echo "CEs added between $prev and $today:"
      echo
      cat "$added_report"
    else
      echo "Subject: ${subject_prefix}No CEs added between $prev and $today"
      echo
      echo "No CEs added between $prev and $today"
    fi
  } | /usr/sbin/sendmail -t
  } </dev/null &>>"$logdir/emailer.$today.$prev.log" &
}


topo-ces.py --getxml > "$datadir/ce_resources.$today.xml"

do_email_report "$yesterday"

if [[ $weekday = Mon ]]; then
  do_email_report "$lastweek" "Weekly summary - " Y
fi

if [[ $monthday = 01 ]]; then
  do_email_report "$lastmonth" "Monthly summary - " Y
fi

