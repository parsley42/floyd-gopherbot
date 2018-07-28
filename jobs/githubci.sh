#!/bin/bash -e

# githubci.sh - a Bash job triggered by github commits

GITHUB_REPOSITORY=$1
GITHUB_BRANCH=$2
shift 2

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

Say "Hey! I see there's a new commit to '$GITHUB_REPOSITORY' in the '$GITHUB_BRANCH' branch. Gonna do something about that real soon!"
