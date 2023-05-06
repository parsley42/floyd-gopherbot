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
when "catchall", "subscribed"
  ai = OpenAI_API.new(bot, direct: direct, botalias: botalias, botname: botname)
  unless ai.status.valid
    if ai.status.error
      bot.ReplyThread(ai.status.error)
    end
    exit(0)
  end
  prompt = ARGV.shift()
  if cmdmode == "name"
    prompt = "#{botname}, #{prompt}"
  end
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
## END OF CONVERSATION HANDLING

when "status"
  if bot.threaded_message or direct
    ai = OpenAI_API.new(bot, "",
      init_conversation: false,
      remember_conversation: true,
      force_thread: false,
      direct: direct,
      debug: false
    )
    if ai.status.valid
      bot.Reply("I hear you and remember an AI conversation totalling #{ai.status.tokens} tokens")
    else
      if ai.status.error
        bot.Reply(ai.status.error)
      else
        bot.Reply("I hear you, but I have no memory of a conversation in this thread; my short-term is only about half a day - you can start a new AI conversation by addressing me in the main channel")
      end
    end
  else
    bot.Reply("I can hear you")
  end
when "image"
  ai = OpenAI_API.new(bot, profile,
    init_conversation: false,
    remember_conversation: false,
    force_thread: true,
    direct: direct,
    debug: debug
  )
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
when "token"
  rep = bot.PromptUserForReply("SimpleString", "OpenAI token?")
  unless rep.ret == Robot::Ok
    bot.SayThread("I had a problem getting your token")
    exit
  end
  token = rep.to_s
  token_memory = bot.CheckoutDatum(OpenAI_API::TokenMemory, true)
  if not token_memory.exists
      token_memory.datum = {}
  end
  tokens = token_memory.datum
  tokens[bot.user] = token
  bot.UpdateDatum(token_memory)
  bot.SayThread("Ok, I stored your personal OpenAI token")
when "rmtoken"
  token_memory = bot.CheckoutDatum(OpenAI_API::TokenMemory, true)
  if not token_memory.exists
      bot.SayThread("I don't see any tokens linked")
      bot.CheckinDatum(token_memory)
      exit
  end
  tokens = token_memory.datum
  if tokens[bot.user]
    tokens.delete(bot.user)
    bot.UpdateDatum(token_memory)
    bot.SayThread("Removed")
    exit
  end
  bot.SayThread("I don't see a token for you")
end
