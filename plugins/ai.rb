#!/usr/bin/ruby

# load the Gopherbot ruby library and instantiate the bot
require 'gopherbot_v1'
bot = Robot.new()

# Found it Floyd's /lib
require 'gopher-ai'

command = ARGV.shift()

defaultConfig = <<'DEFCONFIG'
---
DEFCONFIG

case command
when "init"
  exit(0)
when "configure"
  # puts(defaultConfig)
  exit(0)
end

direct = (bot.channel == "")
cmdmode = ENV["GOPHER_CMDMODE"]

botalias = bot.GetBotAttribute("alias").attr
botname = bot.GetBotAttribute("name").attr

# When command mode = "alias", reproduce the logic of builtin-fallback
if command == "catchall" and cmdmode == "alias"
  if direct
    bot.Say("Command not found; try your command in a channel, or use '#{botalias}help'")
  else
    bot.SayThread("No command matched in channel '#{ENV["GOPHER_CHANNEL"]}'; try '#{botalias}help'")
  end
  exit(0)
end

case command
# For dedicated AI channels, use a MessageMatcher of .* and ChannelOnly: true
when "ambient", "catchall", "subscribed"
  ai = OpenAI_API.new(bot, direct: direct, botalias: botalias, botname: botname)
  unless ai.status.valid
    if ai.status.error
      bot.ReplyThread(ai.status.error)
    end
    exit(0)
  end
  prompt = ARGV.shift()
  cfg = ai.cfg
  unless ai.status.in_progress
    hold_messages = cfg["WaitMessages"]
    hold_message = bot.RandomString(hold_messages)
    bot.Subscribe()
    bot.ReplyThread("(#{hold_message})")
  else
    bot.Say("(#{bot.RandomString(OpenAI_API::ThinkingStrings)})")
  end
  type = ai.status.in_progress ? "continuing" : "starting"
  bot.Log(:debug, "#{type} AI conversation with #{ENV["GOPHER_USER"]} in #{ENV["GOPHER_CHANNEL"]}/#{ENV["GOPHER_THREAD_ID"]}")
  aibot, reply = ai.query(prompt)
  aibot.Say(reply)
when "close"
  ai = OpenAI_API.new(bot, direct: direct, botalias: botalias, botname: botname)
  unless ai.status.valid
    if ai.status.error
      bot.ReplyThread(ai.status.error)
    end
    exit(0)
  end
  if ai.status.in_progress
    if direct
      bot.Say("Ok, I'll forget this conversation")
    else
      bot.Say("Ok, I'll forget this conversation and unsubscribe this thread")
    end
    ai.reset()
  else
    if direct or bot.threaded_message
      bot.Say("I have no memory of a conversation in progress")
    else
      bot.Say("That command doesn't apply in this context")
    end
  end
when "status"
  if bot.threaded_message or direct
    ai = OpenAI_API.new(bot, direct: direct, botalias: botalias, botname: botname)
    if ai.status.valid
      if ai.status.in_progress
        bot.Reply("I hear you and remember an AI conversation totalling #{ai.status.tokens} tokens")
      else
        bot.Reply("I hear you, but I have no memory of a conversation in this thread; my short-term is only about half a day - you can start a new AI conversation by addressing me in the main channel")
      end
    else
      bot.Reply(ai.status.error)
    end
  else
    bot.Reply("I can hear you")
  end
when "image"
  ai = OpenAI_API.new(bot, direct: direct, botalias: botalias, botname: botname)
  unless ai.valid
    bot.SayThread(ai.error)
    exit(0)
  end
  cfg = ai.cfg
  hold_messages = cfg["DrawMessages"]
  hold_message = bot.RandomString(hold_messages)
  bot.Say("(#{hold_message})")
  url = ai.draw(ARGV.shift)
  bot.Say(url)
when "debug"
  unless bot.threaded_message or direct
    bot.SayThread("You can only initialize debugging in a conversation thread")
    exit(0)
  end
  bot.Remember(OpenAI_API::ShortTermMemoryDebugPrefix + ":" + bot.thread_id, "true", true)
  bot.SayThread("(ok, debugging output is enabled for this conversation)")
end
