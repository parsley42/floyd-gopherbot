#!/bin/bash -e

# code.sh - 'vanity' plugin to launch a Cloud9 developer workstation spot instance

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

COMMAND=$1
shift

configure(){
  cat <<"EOF"
Users: [ 'parsley' ]
AllowDirect: true
Help:
- Keywords: [ "wake", "bender" ]
  Helptext: [ "(bot), wake bender - get Bender up and running for development" ]
CommandMatchers:
- Command: "wake"
  Regex: '(?i:wake bender)'
EOF
}

case "$COMMAND" in
	"configure")
		configure
		;;
  "code")
    Say "Ok, I'll see if I can rouse Bender and let you know when he's awake..."
    AddTask bender
    AddTask notify $GOPHER_USER "Bender is up, have at it!"
    FailTask notify $GOPHER_USER "Couldn't wake Bender - check history for the 'bender' job"
    ;;
esac
