#!/usr/bin/ruby

# load the Gopherbot ruby library and instantiate the bot
require 'gopherbot_v1'
bot = Robot.new()

# Found it Floyd's /lib
require 'gopher-ai'

command = ARGV.shift()

defaultConfig = <<'DEFCONFIG'
---
## n.b. All of this can be overridden with custom config in
## conf/plugins/<pluginname>.yaml. Hashes are merged with custom
## config taking precedence. Arrays can be overwritten, or appended
## by defining e.g. AppendWaitMessages: [ ... ]
## ... and remember, yamllint is your friend.
AllowDirect: true
Help:
- Keywords: [ "draw", "image", "paint" ]
  Helptext:
  - "(bot), draw <description> - generate an image with OpenAI Dall-E"
- Keywords: [ "ai", "prompt", "query" ]
  Helptext:
  - "(bot), prompt <query> - start a new threaded conversation with OpenAI"
  - "(bot), p: <query> - shorthand for prompt"
  - "(bot), r(egenerate) - re-send the previous prompt"
  - "(bot), continue <follow up> - continue the conversation with the AI (threads only)"
  - "(bot), c: <follow up> - shorthand for continue the conversation with the AI (threads only)"
  - "(bot), ai <query> - send a single query to OpenAI, generating a reply in the channel"
  - "(bot), add-token - add your personal OpenAI token (robot will prompt you in a DM)"
  - "(bot), remove-token - remove your personal OpenAI token"
  - "(bot), debug-ai - add debugging output during interactions"
  - "(bot), ai-status - in a thread, give conversation status"
CommandMatchers:
- Command: 'prompt'
  Regex: '(?i:p(?:rompt)?(?:=([\w-]+))?(?:/(debug)?)?[: ]\s*(.*))'
- Command: 'debug'
  Regex: '(?i:d(ebug[ -]ai)?)'
- Command: 'status'
  Regex: '(?i:ai[ -]status)'
- Command: 'regenerate'
  Regex: '(?i:r(egenerate|etry|epeat)?)'
- Command: 'ai'
  Regex: '(?i:ai(?:=([\w-]+)?(?:/(debug))?)?[: ]\s*(.*))'
- Command: 'image'
  Regex: '(?i:(?:draw|paint|image)\s*(.*))'
- Command: 'continue'
  Regex: '(?i:c(?:ontinue)?[: ]\s*(.*))'
- Command: 'token'
  Regex: '(?i:(?:link|add|set)[ -]token)'
- Command: 'rmtoken'
  Regex: '(?i:(?:rm|remove|unlink|delete|unset)[ -]token)'
Config:
## Generated with help from an earlier version of the plugin
  WaitMessages:
  - "please be patient while I contact the great mind of the web"
  - "hold on while I connect to the all-knowing oracle"
  - "just a moment while I get an answer from the digital diviner"
  - "give me a second while I reach out to the cosmic connector"
  - "stand by while I consult the infinite intelligence"
  - "hang tight while I access the virtual visionary"
  - "one moment while I check in with the omniscient overseer"
  - "sit tight while I access the all-seeing sage"
  - "wait here while I query the network navigator"
  - "hang on while I communicate with the digital prophet"
  - "wait here a moment while I talk to the universal wisdom"
  - "just a sec while I reach out to the high-tech guru"
  - "hold on a bit while I contact the technological titan"
  - "be right back while I get an answer from the techno telepath"
  DrawMessages:
  - "give us a sec - our AI is brushing up on its drawing skills..."
  - "hang tight - the AI is taking a moment to gather inspiration from its favorite memes"
  - "chill for a moment - our AI is meditating on the perfect color scheme for your image"
  - "please hold while the AI practices its signature for your image"
  - "sit tight while our AI sharpens its pencils... metaphorically, of course"
  - "hang on - the AI is taking a quick break to refuel on coffee and creativity"
  - "one sec - our AI is warming up its digital paintbrush for your image"
  - "please wait while the AI daydreams about your picture-perfect image"
  - "hang on, our AI is putting on its creative thinking cap for your image"
  - "please wait - the AI is doing a quick sketch of your image in its mind before getting started"
  - "please hold while the AI takes a moment to visualize your masterpiece"
  - "relax for a moment - our AI is doing some calisthenics to get pumped up for your image"
  - "please join the AI in taking a deep breath - it's getting ready to bring your vision to life!"
  - "please wait while the AI puts on some classical music to get in the zone"
  Profiles:
    "default":
      "params":
        "model": "gpt-3.5-turbo"
        "temperature": 0.77
      "system": |
        You are ChatGPT, a large language model trained by OpenAI. Answer as correctly as possible.
      "max_context": 3072
DEFCONFIG

case command
when "init"
  exit(0)
when "configure"
  puts(defaultConfig)
  exit(0)
end

# success = bot.Exclusive("ai", false)
# exit(0)

direct = (bot.channel == "")

case command
# All the conversation commands
# "catchall" for all messages sent to Floyd that didn't match other commands
# "subscribed" for all messages in a subscribed thread
# "continue" for an explicit continuation
# "ai" for one-shot (non-continuing) queries
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
