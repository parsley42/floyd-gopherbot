#!/bin/bash -e

# util.sh - shortcut plugin for a variety of actions

source $GOPHER_INSTALLDIR/lib/gopherbot_v1.sh

COMMAND=$1
shift

configure(){
  cat <<"EOF"
AllowedPrivateCommands:
- dinner
- moredinner
Commands:
- Command: "dinner"
  Regex: "(?i:(what's for )?dinner\\??)"
  Usage: "dinner?"
  Summary: "pick random dinner meals"
  Keywords: [ "dinner" ]
- Command: "moredinner"
  Regex: "more dinner please"
  Usage: "more dinner please"
  Summary: "pick another dinner meal"
  Keywords: [ "dinner" ]
EOF
}

case "$COMMAND" in
  "_init")
    if [ ! -e ".wokeup" ]
    then
      SendChannelMessage "general" "Oh boy! Are we gonna try something dangerous now?"
      touch ".wokeup"
    fi
    ;;
  "_configure")
    configure
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
