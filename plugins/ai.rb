#!/usr/bin/ruby

## TODO:
## - Add user parameter, hash of robot name and slack user ID;
##   see: https://beta.openai.com/docs/guides/safety-best-practices/end-user-ids
## - Add retry/repeat/regenerate to send the previous prompt again;
##   note that this will need to pop the last exchange off of exhanges
##   and re-send the human part
## - Augment debugging to include the preamble plus a truncated version of exchanges

# load the Gopherbot ruby library and instantiate the bot
require 'gopherbot_v1'
bot = Robot.new()

command = ARGV.shift()

defaultConfig = <<'DEFCONFIG'
---
AllowDirect: true
Help:
- Keywords: [ "ai", "prompt", "query" ]
  Helptext:
  - "(bot), prompt <query> - start a new threaded conversation with OpenAI"
  - "(bot), p: <query> - shorthand for prompt"
  - "(bot), continue <follow up> - continue the conversation with the AI (threads only)"
  - "(bot), c: <follow up> - shorthand for continue the conversation with the AI (threads only)"
  - "(bot), ai <query> - send a single query to OpenAI, generating a reply in the channel"
  - "(bot), add-token - add your personal OpenAI token (robot will prompt you in a DM)"
  - "(bot), remove-token - remove your personal OpenAI token"
  - "(bot), debug-ai - add debugging output during interactions"
CommandMatchers:
- Command: 'prompt'
  Regex: '(?i:p(?:rompt)?(?:=([\w-]+)?(?:/(debug))?)?[: ]\s*(.*))'
- Command: 'debug'
  Regex: '(?i:debug[ -]ai)'
- Command: 'ai'
  Regex: '(?i:ai(?:=([\w-]+)?(?:/(debug))?)?[: ]\s*(.*))'
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
## This should only be enabled in alternate configurations for the plugin,
## where `AllowDirect` is set to 'false' and only a single application
## channel is specified.
# Channels:
# - ai
# AllowDirect: false
# Help:
# - Keywords: [ "ai", "prompt", "query" ]
#   Helptext:
#   - "<query> - Start or continue a threaded conversation with OpenAI (all messages)"
# MessageMatchers:
# - Command: 'ambient'
#   Regex: '(.*)'
# Config:
#   AmbientChannel: "ai"
DEFCONFIG

case command
when "init"
  system("gem install --user-install --no-document ruby-openai")
  exit(0)
when "configure"
  puts(defaultConfig)
  exit(0)
end

require "ruby/openai"
require 'json'
require 'base64'
require 'digest/sha1'

class AIPrompt
  attr_reader :valid, :error, :cfg

  TokenMemory = "usertokens"
  ShortTermMemoryPrefix = "ai-conversation"
  ShortTermMemoryDebugPrefix = "ai-debug"
  DefaultProfile = "default"
  ## Used when plugin configuration doesn't include a given profile
  FallbackSettings = {
    "params" => {
      "model" => "text-davinci-003",
      "temperature" => 0.91,
      "max_tokens" => 1001,
      "n" => 1,
      "top_p" => 1,
      "frequency_penalty" => 0.3,
      "presence_penalty" => 0.4,
      "stop" => ["Human:", "AI:"]
    },
    "ai_string" => "AI:",
    "user_string" => "Human:",
    "preamble" => "Human: Who are you?\nAI: I am an AI created by OpenAI. How can I help you?"
  }

  def initialize(bot, profile,
      init_conversation:,
      remember_conversation:,
      force_thread:,
      direct:,
      debug:
    )
    # We don't default the var because it could be just set to a zero-length string ("")
    unless profile and profile.length > 0
      profile = DefaultProfile
    end
    @force_thread = force_thread
    @bot = @force_thread ? bot.Threaded : bot
    @direct = direct
    @memory = @direct ? ShortTermMemoryPrefix : ShortTermMemoryPrefix + ":" + bot.thread_id
    @profile = profile
    @exchanges = []
    @valid = true
    @remember_conversation = remember_conversation
    @init_conversation = init_conversation
    debug_memory = @bot.Recall(ShortTermMemoryDebugPrefix + ":" + bot.thread_id)
    @debug = (debug_memory.length > 0 or debug)

    if (bot.threaded_message or @direct) and @remember_conversation and not @init_conversation
      encoded_state = bot.Recall(@memory)
      state = decode_state(encoded_state)
      profile, exchanges = state.values_at("profile", "exchanges")
      if exchanges.length > 0
        @exchanges = exchanges
        @profile = profile
      else
        unless init_conversation
          @valid = false
          @error = "Sorry, I've forgotten what we were talking about"
        end
      end
    end
    @cfg = bot.GetTaskConfig()
    @settings = @cfg["Profiles"][@profile]
    unless @settings
      @settings = FallbackSettings
      @bot.Log(:warn, "no settings found for profile #{@profile}, using fallback settings")
    end

    @org = ENV["OPENAI_ORGANIZATION_ID"]
    token = get_token()
    unless token and token.length > 0
      @valid = false
      botalias = @bot.GetBotAttribute("alias")
      @error = "Sorry, you need to add your token first - try '#{botalias}help'"
    end
    Ruby::OpenAI.configure do |config|
      config.access_token = token
      if @org
        config.organization_id = @org
      end
    end
    @client = OpenAI::Client.new
  end

  def query(input)
    while true
      prompt = build_prompt(input)
      if @bot.channel == "mock" and @bot.protocol == "terminal"
        puts("DEBUG full prompt:\n#{prompt}")
      end
      parameters = @settings["params"]
      parameters["user"] = Digest::SHA1.hexdigest(ENV["GOPHER_USER_ID"])
      if @debug
        @bot.Say("Query parameters: #{parameters.to_json}", :fixed)
        @bot.Say("Prompt: #{prompt}", :fixed)
      end
      parameters["prompt"] = prompt
      response = @client.completions(parameters: parameters)
      if @debug
        @bot.Say("Response: #{response.to_json}", :fixed)
      end
      if response["error"]
        message = response["error"]["message"]
        if message.match?(/tokens/i)
          @exchanges.shift
          @bot.Log(:warn, "token error, dropping an exchange and re-trying")
          next
        end
        @bot.SayThread("Sorry, there was an error - '#{message}'")
        @bot.Log(:error, "connecting to openai: #{message}")
        exit(0)
      end
      aitext = response["choices"][0]["text"].lstrip
      usage = response["usage"]
      @bot.Log(:debug, "usage: prompt #{usage["prompt_tokens"]}, completion #{usage["completion_tokens"]}, total #{usage["total_tokens"]}")
      break
    end
    aitext.strip!
    if input.length > 0
      @exchanges << {
        "human" => input,
        "ai" => aitext
      }
    end
    if @remember_conversation
      @bot.Remember(@memory, encode_state)
    end
    return @bot, aitext
  end

  def build_prompt(input)
    prompt = @settings["preamble"] + "\n"
    final = nil
    if input.length > 0
      final = "Human: #{input}\nAI:"
    end
    @exchanges.each do |exchange|
      exchange_string = exchange_string(exchange)
      prompt += exchange_string
    end
    if final
      prompt += final
    end
    return prompt
  end

  def get_token
    token = nil
    token_memory = @bot.CheckoutDatum(TokenMemory, false)
    if token_memory.exists
      token = token_memory.datum[@bot.user]
      if token
        @bot.Log(:info, "Using personal token for #{@bot.user}")
        @org = nil
      end
    end
    unless token
      token = ENV['OPENAI_KEY']
      @bot.Log(:info, "Using global token for #{@bot.user} (org: #{@org})") if token
    end
    @bot.Log(:error, "No OpenAI token found for request from user #{@bot.user}") unless token
    return token
  end

  def encode_state
    state = {
      "profile": @profile,
      "exchanges": @exchanges
    }
    json = state.to_json
    Base64.strict_encode64(json)
  end

  def decode_state(encoded_state)
    unless encoded_state and encoded_state.length > 0
      return {
        "profile" => "",
        "exchanges" => []
      }
    end
    json = Base64.strict_decode64(encoded_state)
    JSON.parse(json)
  end

  def exchange_string(exchange)
    return "#{@settings["user_string"]} #{exchange["human"]}\n#{@settings["ai_string"]} #{exchange["ai"]}\n"
  end
end

direct = (bot.channel == "")

case command
when "ambient", "prompt", "ai", "continue"
  init_conversation = false
  remember_conversation = true
  force_thread = false
  debug = false
  if direct and command == "ai"
    command = "prompt"
  end
  if command == "ambient" or command == "continue"
    profile = ""
    prompt = ARGV.shift
  else
    profile, debug, prompt = ARGV.shift(3)
  end
  case command
  when "ambient"
    init_conversation = true unless bot.threaded_message
    force_thread = true
  when "ai"
    init_conversation = true
    remember_conversation = false
    if debug and debug.length > 0
      debug = true
    end
  when "prompt"
    init_conversation = true
    force_thread = true unless direct
    if debug and debug.length > 0
      bot.RememberThread(AIPrompt::ShortTermMemoryDebugPrefix + ":" + bot.thread_id, "true")
      debug = true
    end
  when "continue"
    unless direct or bot.threaded_message
      bot.SayThread("Sorry, you can't continue AI conversations in a channel")
      exit(0)
    end
    init_conversation = false
  end
  ai = AIPrompt.new(bot, profile,
    init_conversation: init_conversation,
    remember_conversation: remember_conversation,
    force_thread: force_thread,
    direct: direct,
    debug: debug
  )
  unless ai.valid
    bot.SayThread(ai.error)
    exit(0)
  end
  cfg = ai.cfg
  if init_conversation
    hold_messages = cfg["WaitMessages"]
    hold_message = bot.RandomString(hold_messages)
    if command == "ai"
      bot.Say("(#{hold_message})")
    else
      bot.SayThread("(#{hold_message})")
    end
  end
  aibot, reply = ai.query(prompt)
  aibot.Say(reply)
  ambient_channel = cfg["AmbientChannel"]
  ambient = ambient_channel && ambient_channel == bot.channel
  if remember_conversation and (direct or not ambient) and (command != "continue")
    botalias = bot.GetBotAttribute("alias").attr
    follow_up_command = direct ? "c:" : botalias + "c"
    aibot.Say("(use '#{follow_up_command} <follow-up text>' to continue the conversation)")
  end
when "debug"
  unless bot.threaded_message
    bot.SayThread("You can only initialize debugging in a conversation thread")
    exit(0)
  end
  bot.Remember(AIPrompt::ShortTermMemoryDebugPrefix + ":" + bot.thread_id, "true")
  bot.SayThread("(ok, debugging output is enabled for this conversation)")
when "token"
  rep = bot.PromptUserForReply("SimpleString", "OpenAI token?")
  unless rep.ret == Robot::Ok
    bot.SayThread("I had a problem getting your token")
    exit
  end
  token = rep.to_s
  token_memory = bot.CheckoutDatum(AIPrompt::TokenMemory, true)
  if not token_memory.exists
      token_memory.datum = {}
  end
  tokens = token_memory.datum
  tokens[bot.user] = token
  bot.UpdateDatum(token_memory)
  bot.SayThread("Ok, I stored your personal OpenAI token")
when "rmtoken"
  token_memory = bot.CheckoutDatum(AIPrompt::TokenMemory, true)
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
