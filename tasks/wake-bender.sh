#!/bin/bash

# wake-bender.sh - task for launching and configuring a Gopherbot dev instance

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
    AddTask wake-bender launch
    AddTask wake-bender configure
    ;;
esac