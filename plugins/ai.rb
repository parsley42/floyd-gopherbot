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

# When command mode = "alias", reproduce the logic of builtin-fallback
if command == "catchall" and cmdmode == "alias"
  botalias = bot.GetBotAttribute("alias")
  if direct
    bot.Say("Command not found; try your command in a channel, or use '#{botalias}help'")
  else
    bot.SayThread("No command matched in channel '#{ENV["GOPHER_CHANNEL"]}'; try '#{botalias}help'")
  end
end

case command
# All the conversation commands
# "catchall" for all messages sent to Floyd that didn't match other commands
# "subscribed" for all messages in a subscribed thread
# "regenerate" to resend the last query
when "subscribed", "prompt", "ai", "continue", "regenerate", "catchall"
  bot.Log(:debug, "handling conversation command '#{command}' from #{ENV["GOPHER_USER"]}/#{ENV["GOPHER_USER_ID"]} in channel #{ENV["GOPHER_CHANNEL"]}/t:#{ENV["GOPHER_THREAD_ID"]}")
  init_conversation = false
  remember_conversation = true
  force_thread = false
  debug = false
  catchall = false
  debug_flag = nil
  botalias = bot.GetBotAttribute("alias").attr
  if direct and command == "ai"
    command = "prompt"
  end
  if command == "subscribed" or command == "continue" or command == "catchall"
    profile = ""
    prompt = ARGV.shift
  else
    profile, debug_flag, prompt = ARGV.shift(3)
  end
  regenerate = false
  if command == "regenerate"
    regenerate = true
    prompt = ""
    command = "continue"
  end
  if command == "catchall"
    catchall = true
    if direct
      short_term_memory = bot.Recall(OpenAI_API::ShortTermMemoryPrefix, true)
      if short_term_memory.length > 0
        bot.Remember(OpenAI_API::ShortTermMemoryPrefix, short_term_memory, true)
        command = "continue"
      else
        command = "prompt"
      end
    else
      command = "subscribed"
    end
  end
  case command
  when "subscribed"
    init_conversation = true unless bot.threaded_message
    force_thread = true
  when "ai"
    init_conversation = true
    remember_conversation = false
    if debug_flag and debug_flag.length > 0
      debug = true
    end
  when "prompt"
    init_conversation = true
    force_thread = true unless direct
    if debug_flag and debug_flag.length > 0
      bot.RememberThread(OpenAI_API::ShortTermMemoryDebugPrefix + ":" + bot.thread_id, "true")
      debug = true
    end
  when "continue"
    unless direct or bot.threaded_message
      action = regenerate ? "regenerate" : "continue"
      bot.SayThread("Sorry, you can't #{action} AI conversations in a channel")
      exit(0)
    end
    init_conversation = false
  end
  ai = OpenAI_API.new(bot, profile,
    init_conversation: init_conversation,
    remember_conversation: remember_conversation,
    force_thread: force_thread,
    direct: direct,
    debug: debug
  )
  unless ai.status.valid
    if ai.status.error
      bot.ReplyThread(ai.status.error)
    else
      if catchall
        bot.Reply("Sorry, I don't remember a conversation with you in this thread - but you can start a new AI converstaion with me in the main channel")
      end
      bot.Log(:debug, "ignoring message from #{ENV["GOPHER_USER"]} in #{ENV["GOPHER_CHANNEL"]}/#{ENV["GOPHER_THREAD_ID"]} - no conversation memory")
    end
    exit(0)
  end
  cfg = ai.cfg
  if init_conversation
    hold_messages = cfg["WaitMessages"]
    hold_message = bot.RandomString(hold_messages)
    if command == "ai"
      bot.Say("(#{hold_message})")
    else
      bot.Subscribe()
      bot.ReplyThread("(#{hold_message})")
    end
  else
    bot.Say("(#{bot.RandomString(OpenAI_API::ThinkingStrings)})")
  end
  type = init_conversation ? "starting" : "continuing"
  bot.Log(:debug, "#{type} AI conversation with #{ENV["GOPHER_USER"]} in #{ENV["GOPHER_CHANNEL"]}/#{ENV["GOPHER_THREAD_ID"]}")
  aibot, reply = ai.query(prompt, regenerate)
  aibot.Say(reply)
  ambient_channel = cfg["AmbientChannel"]
  ambient = ambient_channel && ambient_channel == bot.channel
  if remember_conversation and (direct or not ambient) and (command != "continue")
    follow_up_command = direct ? "c:" : botalias + "c"
    regenerate_command = direct ? "r" : botalias + "r"
    prompt_command = direct ? "p" : botalias + "p"
    if catchall
      aibot.Say("(use '#{prompt_command} <query>' to start a new conversation, or '#{regenerate_command}' to re-send the last prompt)")
    else
      aibot.Say("(use '#{follow_up_command} <follow-up text>' to continue the conversation, or '#{regenerate_command}' to re-send the last prompt)")
    end
  end
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
