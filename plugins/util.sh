#!/bin/bash -e

# util.sh - shortcut plugin for a variety of actions

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

COMMAND=$1
shift

configure(){
  cat <<"EOF"
AllowDirect: true
Help:
- Keywords: [ "dinner" ]
  Helptext: [ "(bot), dinner? - pick random dinner meals" ]
CommandMatchers:
- Command: "dinner"
  Regex: "(?i:(what's for )?dinner\\??)"
- Command: "moredinner"
  Regex: "more dinner please"
EOF
}

case "$COMMAND" in
  "init")
    if [ ! -e ".wokeup" ]
    then
      SendChannelMessage "ai" "Floyd here now!"
      touch ".wokeup"
    fi
    ;;
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
    AddCommand util "more dinner please"
    ;;
  "moredinner")
    if MORE=$(PromptForReply YesNo "Pick another?")
    then
      case $MORE in
        y | Y | Yes | yes)
          AddCommand lists "pick a random item from the dinner meals list"
          AddCommand util "more dinner please"
          ;;
        *)
          Say "Bon Apetit!"
          ;;
      esac
    else
      Say "Ok then, ttyl!"
    fi
esac
