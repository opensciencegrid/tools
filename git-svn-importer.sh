#!/bin/bash
set -e

usage () {
  echo "$(basename "$0") project"
  exit
}

case $1 in
  ''|-* ) usage ;;
      * ) project=$1 ;;
esac

tmpd=$(mktemp -d)
#trap 'rm -rf "$tmpd"' EXIT

cd "$tmpd"

git svn clone --authors-file /p/condor/workspaces/vdt/svn-access/authors.txt \
    --stdlayout "file:///p/condor/workspaces/vdt/svn/software/$project"

cd "$project"

filter_branch () {
  git filter-branch -f --msg-filter '
    awk '\''
       /^git-svn-id:/ {print > "git-svn-note.txt"}
      !/^git-svn-id:/ {print}
    '\''

    sed -ri '\''
      s!^git-svn-id: file:///p/condor/workspaces/vdt/svn/!!;
      s/ .*$//;
      s/^(.*)@([0-9]+)$/r\2 \1/;
    '\'' git-svn-note.txt
  ' --commit-filter '
    NEW_COMMIT=$(git commit-tree "$@")
    echo $NEW_COMMIT
    git notes add -f -F git-svn-note.txt $NEW_COMMIT
  ' "$@" 2> >(grep -v "^Overwriting existing notes for object" >&2)
}

if [[ $(git rev-parse master) = $(git rev-parse trunk) ]]; then
  git branch -rd trunk
fi

filter_branch
for x in $(git branch -r); do
  filter_branch "$x"
  case $x in
      tags/* ) git tag "${x#tags/}" "$x" ;;
    *@[1-9]* ) git tag "$x" "$x" ;;
           * ) git branch "$x" refs/remotes/"$x" ;;
  esac
  git branch -rd "$x"
done

git prune
git gc

if [[ $DISPLAY ]]; then
  gitk &
fi

echo
echo "checkout left in $tmpd/$project"
echo

