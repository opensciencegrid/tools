#!/bin/bash
set -e

# OBSOLETE: this was a proof of concept to show that all the features of
#           subgit (including per-revision git notes) can be accomplished
#           with the standard git-svn tool.
#
#           Use 'git-svn-bare-setup' instead.

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

for x in $(git branch -r | grep @); do
  # remove superfluous git-svn 'branch points'
  if git branch -a --contains refs/remotes/$x | grep -vq @; then
    git branch -rD $x
  fi
done

filter_branch
for x in $(git branch -r); do
  filter_branch refs/remotes/"$x"
  case $x in
      tags/*@[1-9]* ) git tag "${x#tags/}"-tag refs/remotes/"$x" ;;
      tags/* ) git tag "${x#tags/}" refs/remotes/"$x" ;;
    *@[1-9]* ) git tag "$x" refs/remotes/"$x" ;;
           * ) git branch "$x" refs/remotes/"$x" ;;
  esac
  git branch -rd "$x"
done

rm -rf .git/svn .git/refs/original
git reflog expire --expire=now --all
git gc --prune=now

if [[ $DISPLAY ]]; then
  gitk &
fi

echo
echo "checkout left in $tmpd/$project"
echo

