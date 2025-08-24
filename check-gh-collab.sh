#!/bin/bash

usage () {
    echo "Usage: check-collab.sh <GITHUB ORG> <GITHUB USERNAME>"
    exit 1
}

[[ $# -ne 2 ]] && usage

ORG=$1
USER=$2

REPOS_PER_PAGE=100

# TODO: figure out a  way to find the last page containing repos
for i in $(seq 5); do
    repos+=$(curl --stderr /dev/null \
                  -H "Authorization: token $(cat ~/.github/oauth2)" \
                  -H "Accept: application/vnd.github.v3+json" "https://api.github.com/orgs/$ORG/repos?per_page=$REPOS_PER_PAGE&page=$i" \
                 | jq ".[].full_name" \
                 | tr -d '"')
done

echo "$USER is a collaborator on the following repositories:"

for repo in ${repos[*]}; do
    response=$(curl -o /dev/null \
                    --stderr /dev/null \
                    -H "Authorization: token $(cat ~/.github/oauth2)" \
                    -w "%{http_code}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$repo/collaborators/$USER")
    # https://docs.github.com/en/rest/reference/collaborators#check-if-a-user-is-a-repository-collaborator
    if [[ $response == "204" ]]; then
        echo "- $repo"
    fi
done
