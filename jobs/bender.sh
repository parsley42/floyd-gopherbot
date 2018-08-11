#!/bin/bash

# bender.sh - job for setting up Bender.

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

# Don't queue if this build in progress, just exit
if ! Exclusive Bender false
then
    Log Warn "Job 'bender' already in progress, exiting"
    exit 0
fi

# Stuff that happens "right now"
mkdir -p $GOPHER_WORKSPACE/bender
SetWorkingDirectory bender
# The ansible-vault passphrase is stored in ansible:github.com/parsley42/aws-devel VAULT_PASSWORD=<foo>
# Namespaces defined in repositories.yaml
ExtendNamespace github.com/parsley42/deploy-gopherbot 21

# Set up the pipeline; all tasks must be defined in gopherbot.yaml
AddTask ssh-init
AddTask ssh-scan bitbucket.org
AddTask git-sync git@bitbucket.org:lnxjedi/linuxjedi-private.git linuxjedi-private
AddTask git-sync https://github.com/parsley42/deploy-gopherbot.git deploy-gopherbot
AddTask git-sync https://github.com/lnxjedi/ansible-role-gopherbot.git lnxjedi.gopherbot
AddTask git-sync https://github.com/parsley42/aws-linuxjedi.git aws-linuxjedi
# The task that actuall builds the workstation
AddTask wake-bender
