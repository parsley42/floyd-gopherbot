#!/bin/bash

# c9wks.sh - job for launching a Cloud9 developer workstation spot instance.

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

# Name of the instance to build
if [ -z "$DEVHOST" ]
then
    DEVHOST=$(GetSenderAttribute name)
    # Export value for the rest of the pipeline
    SetParameter DEVHOST $DEVHOST
fi
if [ -z "$DEVIMG" ]
then
    DEVIMG=amzn2devel
    # Export value for the rest of the pipeline
    SetParameter DEVIMG $DEVIMG
fi

# Don't queue if this build in progress, just exit
if ! Exclusive $DEVHOST false
then
    Log Warn "Job already in progress, exiting"
    exit 0
fi

# Stuff that happens "right now"
mkdir -p $GOPHER_WORKSPACE/c9wks/$DEVHOST
SetWorkingDirectory c9wks/$DEVHOST
# The ansible-vault passphrase is stored in ansible:github.com/parsley42/aws-devel VAULT_PASSWORD=<foo>
# Namespaces defined in repositories.yaml
ExtendNamespace github.com/parsley42/aws-devel/master 21

# Set up the pipeline; all tasks must be defined in gopherbot.yaml
AddTask ssh-init
AddTask ssh-scan bitbucket.org
AddTask git-sync git@bitbucket.org:lnxjedi/linuxjedi-private.git master linuxjedi-private
AddTask git-sync https://github.com/parsley42/aws-devel.git master aws-devel
AddTask git-sync https://github.com/parsley42/aws-linuxjedi.git master aws-linuxjedi
# The task that actuall builds the workstation
AddTask build-c9wks
