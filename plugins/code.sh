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
- Keywords: [ "code", "program" ]
  Helptext: [ "(bot), start coding - launch a Cloud9 developer spot instance" ]
CommandMatchers:
- Command: "code"
  Regex: '(?i:start coding)'
EOF
}

case "$COMMAND" in
	"configure")
		configure
		;;
  "code")
    Say "Ok, I'll start the 'cloud9wks' job and let you know when your workstation is ready..."
    AddTask cloud9wks
    AddTask notify $GOPHER_USER "Happy coding!"
    FailTask notify $GOPHER_USER "Build failed, check history for the 'cloud9wks' job"
    ;;
esac
