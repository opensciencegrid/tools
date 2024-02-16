#!/bin/bash

#  REQUIRES OSG YUM REPOS TO BE INSTALLED  (can run from a Fermi VM)

vrstrip () { perl -lpe 's/(-[^-]+){2}$//' "$@"; }
unique  () { awk '!u[$0]++' "$@"; }

rqpd () { repoquery --plugins --disablerepo=\* "$@"; }

brq  () { rqpd --archlist=x86_64,noarch --enablerepo=osg-development "$@"; }
srq  () { rqpd --archlist=src --enablerepo=osg-development-source "$@"; }

brq_wr () { brq --whatrequires "$@"; }
srq_wr () { srq --whatrequires "$@"; }
brq_s  () { brq --source "$@"; }

dot_header () { echo "digraph deps {"; }
dot_footer () { echo "}"; }
dot_edge   () { echo "  \"$1\" -> \"$2\"${3:+ [color=\"$3\"]};"; }

color_item    () { echo "  \"$1/$2\" [label=\"$2\" color=\"$3\"];"; }
color_install () { color_item install "$1" blue; }
color_build   () { color_item build   "$1" green; }

brq glite-\* > pkglist.arch

dot_header

for x in $(<pkglist.arch ); do
  bpkg=$(echo "$x" | vrstrip)
  bpkg_spkg=$(brq_s "$x" | vrstrip)
  dot_edge "install/$bpkg" "build/$bpkg_spkg" purple
  color_install "$bpkg"
  color_build   "$bpkg_spkg"

  for br_by in $(srq_wr "$bpkg" | vrstrip | sort -u); do
    [[ "$br_by" = "$bpkg" ]] ||  #  <-- just refers to the .src.rpm
    dot_edge "build/$br_by" "install/$bpkg" red
    color_build "$br_by"
  done

  for r_by in $(brq_wr "$bpkg" | vrstrip | sort -u); do
    [[ "$r_by" = "$bpkg" ]] ||
    dot_edge "install/$r_by" "install/$bpkg" orange
    color_install "$r_by"

    r_by_spkg=$(brq_s "$r_by" | vrstrip)
    dot_edge "install/$r_by" "build/$r_by_spkg" purple
    color_build "$r_by_spkg"
  done
done | unique

dot_footer

