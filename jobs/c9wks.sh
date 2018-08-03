#!/bin/bash

# c9wks.sh - job for launching a Cloud9 developer workstation spot instance.

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

# Name of the instance to build
DEVHOST=$(GetSenderAttribute name)
# Export value for the rest of the pipeline
SetParameter DEVHOST $DEVHOST

# Don't queue if this build in progress, just exit
if ! Exclusive $DEVHOST false
then
    exit 0
fi

# Stuff that happens "right now"
mkdir -p $GOPHER_WORKSPACE/c9wks/$DEVHOST
SetWorkingDirectory c9wks/$DEVHOST
# The ansible-vault passphrase is stored in ansible:github.com/parsley42/aws-devel VAULT_PASSWORD=<foo>
# Namespaces defined in repositories.yaml
ExtendNamespace github.com/parsley42/aws-devel 21

# Set up the pipeline; all tasks must be defined in gopherbot.yaml
AddTask ssh-init
AddTask ssh-scan bitbucket.org
AddTask git-sync git@bitbucket.org:lnxjedi/linuxjedi-private.git linuxjedi-private
AddTask git-sync https://github.com/parsley42/aws-devel.git aws-devel
AddTask git-sync https://github.com/parsley42/aws-linuxjedi.git aws-linuxjedi
# The task that actuall builds the workstation
AddTask build-c9wks
