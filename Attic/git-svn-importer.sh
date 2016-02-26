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
       /^git-svn-id:/ {print > "/dev/fd/3"; got_id=1}
      !/^git-svn-id:/ {print}
      END { if (!got_id) {print "" > "/dev/fd/3"} }
    '\''
  ' --commit-filter '
    NEW_COMMIT=$(git commit-tree "$@")
    echo $NEW_COMMIT
    echo $NEW_COMMIT >&4
  ' "$@" 3>> ../git-svn-id-tags.txt 4>> ../git-svn-rewrite-shas.txt
}

add_notes () {
  svn_url=$(git config --local --get svn-remote.svn.url)

  sed -ri '
    s!^git-svn-id: '"$svn_url"'/!!;
    s/ .*$//;
    s/^(.*)@([0-9]+)$/r\2 \1/;
  ' ../git-svn-id-tags.txt

  mkdir ../git-notes
  paste ../git-svn-rewrite-shas.txt ../git-svn-id-tags.txt \
  | awk -F'\t' 'NF==2 && !u[$0]++ {print $2 >> "../git-notes/" $1}'

  
  for sha in $(cd ../git-notes
               grep . * | sort -Vk2 -t: | cut -d: -f1 | awk '!u[$0]++'); do
    git notes add -F ../git-notes/"$sha" "$sha"
  done
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
    origin/tags/*@[1-9]* ) git tag "${x#origin/tags/}"-tag refs/remotes/"$x" ;;
    origin/tags/*   ) git tag "${x#origin/tags/}" refs/remotes/"$x" ;;
    origin/*@[1-9]* ) git tag "${x#origin/}" refs/remotes/"$x" ;;
           origin/* ) git branch "${x#origin/}" refs/remotes/"$x" ;;
  esac
  git branch -rd "$x"
done

add_notes

rm -rf .git/svn .git/refs/original
git reflog expire --expire=now --all
git gc --prune=now

if [[ $DISPLAY ]]; then
  gitk &
fi

echo
echo "checkout left in $tmpd/$project"
echo

