#!/bin/bash -e

# util.sh - shortcut plugin for a variety of actions

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
- Keywords: [ "code", "program" ]
  Helptext: [ "(bot), start workstation - launch a Cloud9 developer spot instance" ]
CommandMatchers:
- Command: "wake"
  Regex: '(?i:wake bender)'
- Command: "code"
  Regex: '(?i:start (?:coding|workstation))'
- Command: "dinner"
  Regex: "(?i:(what's for )?dinner\??)"
EOF
}

case "$COMMAND" in
	"configure")
		configure
		;;
  "code")
    Say "Ok, I'll start the 'cloud9wks' job and let you know when your workstation is ready..."
    AddJob cloud9wks
    AddTask notify $GOPHER_USER "Happy coding!"
    FailTask notify $GOPHER_USER "Build failed, check history for the 'cloud9wks' job"
    ;;
  "wake")
    Say "Ok, I'll see if I can rouse Bender and let you know when he's awake..."
    AddJob bender
    AddTask notify $GOPHER_USER "Bender is up, have at it!"
    FailTask notify $GOPHER_USER "Couldn't wake Bender - check history for the 'bender' job"
    ;;
  "dinner")
    AddCommand lists "pick a random item from the dinner meals list"
    ;;
esac
