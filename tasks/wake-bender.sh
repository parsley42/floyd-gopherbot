#!/bin/bash

# build-c9wks.sh - task for launching and configuring a Cloud9 workstation

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

ACTION=$1

case "$ACTION" in
"launch")
    ec2 create -w bender $KEYNAME gopherdev
    ;;
"configure")
    AddTask ansible-playbook deploy.yaml -e target=bender
    ;;
*)
    SetWorkingDirectory bender/deploy-gopherbot
    AddTask build-c9wks launch
    AddTask build-c9wks configure
    ;;
esac