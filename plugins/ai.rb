#!/usr/bin/ruby

# load the Gopherbot ruby library and instantiate the bot
require 'gopherbot_v1'
bot = Robot.new()

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
CommandMatchers:
- Command: 'prompt'
  Regex: '(?i:p(?:rompt)?(?:=([\w-]+))?(?:/(debug)?)?[: ]\s*(.*))'
- Command: 'debug'
  Regex: '(?i:d(ebug[ -]ai)?)'
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

require "openai"
require 'json'
require 'base64'
require 'digest/sha1'

class OpenAI_API
  attr_reader :valid, :error, :cfg

  TokenMemory = "usertokens"
  ShortTermMemoryPrefix = "ai-conversation"
  ShortTermMemoryDebugPrefix = "ai-debug"
  DefaultProfile = "default"
  PartialLineLength = 42

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
      @profile = "default"
      @settings = @cfg["Profiles"][@profile]
      @bot.Log(:warn, "no settings found for profile #{@profile}, falling back to 'default'")
    end
    @system = @settings["system"]
    @max_context = @settings["max_context"]

    @org = ENV["OPENAI_ORGANIZATION_ID"]
    token = get_token()
    unless token and token.length > 0
      @valid = false
      botalias = @bot.GetBotAttribute("alias")
      @error = "Sorry, you need to add your token first - try '#{botalias}help'"
    end
    OpenAI.configure do |config|
      config.access_token = token
      if @org
        config.organization_id = @org
      end
    end
    @client = OpenAI::Client.new
  end

  def draw(prompt)
    response = @client.images.generate(parameters: { prompt: prompt, size: "512x512" })
    return response.dig("data", 0, "url")
  end

  def query(input, regenerate = false)
    if regenerate
      unless @exchanges.length > 0
        @bot.Say("Eh... I can't recall a previous query")
        exit(0)
      end
      @bot.Say("(ok, I'll re-send the previous chat content)")
      last_exchange = @exchanges.pop
      input = last_exchange["human"]
    end
    while true
      messages, partial = build_messages(input)
      if @bot.channel == "mock" and @bot.protocol == "terminal"
        puts("DEBUG full chat:\n#{messages}")
      end
      parameters = @settings["params"]
      parameters["user"] = Digest::SHA1.hexdigest(ENV["GOPHER_USER_ID"])
      if @debug
        @bot.Say("Query parameters: #{parameters.to_json}", :fixed)
        @bot.Say("Chat (lines truncated):\n#{partial}", :fixed)
      end
      parameters[:messages] = messages
      response = @client.chat(parameters: parameters)
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
      break
    end
    aitext = response["choices"][0]["message"]["content"].lstrip
    if @debug
      ## This monkey business is because .to_json was including
      ## items removed with .delete(...). ?!?
      rdata = {}
      response.each_key do |key|
        next if key == "choices"
        rdata[key] = response[key]
      end
      @bot.Say("Response data: #{rdata.to_json}", :fixed)
    end
    usage = response["usage"]
    @bot.Log(:debug, "usage: prompt #{usage["prompt_tokens"]}, completion #{usage["completion_tokens"]}, total #{usage["total_tokens"]}")
    aitext.strip!
    if @remember_conversation
      if input.length > 0
        @exchanges << {
          "human" => input,
          "ai" => aitext
        }
      end
      current_total = usage["total_tokens"]
      if current_total > @max_context
        @bot.Log(:warn, "conversation length (#{current_total}) exceeded max_context (#{@max_context}), dropping an exchange")
        @exchanges.shift
      end
      @bot.Remember(@memory, encode_state)
    end
    return @bot, aitext
  end

  def build_messages(input)
    messages = [
      {
        role: "system", content: @system
      }
    ]
    partial = String.new
    final = nil
    if input.length > 0
      final = {
        role: "user", content: input
      }
    end
    @exchanges.each do |exchange|
      contents, partial_string = exchange_data(exchange)
      messages += contents
      partial += partial_string
    end
    if final
      messages.append(final)
      partial += "user: #{input}"
    end
    return messages, partial
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

  ## Courtesy of OpenAI / Astro Boy
  def truncate_line(str)
    truncated_str = str.split("\n").first
    if truncated_str.length > PartialLineLength
      truncated_str = truncated_str[0..PartialLineLength-1] + " ..."
    end
    return truncated_str
  end

  def exchange_data(exchange)
    contents = [
      {
        role: "user", content: exchange["human"]
      },
      {
        role: "assistant", content: exchange["ai"]
      }
    ]
    human_line = "user: #{exchange["human"]}"
    ai_line = "assistant: #{exchange["ai"]}"
    partial = "#{truncate_line(human_line)}\n#{truncate_line(ai_line)}\n"
    return contents, partial
  end
end

direct = (bot.channel == "")
case command
when "ambient", "prompt", "ai", "continue", "regenerate", "catchall"
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
  if command == "ambient" or command == "continue" or command == "catchall"
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
    if prompt.start_with?(botalias)
      bot.Say("No command matched; try '#{botalias}help', or '#{botalias}help ai'")
    end
    catchall = true
    if direct
      short_term_memory = bot.Recall(OpenAI_API::ShortTermMemoryPrefix)
      if short_term_memory.length > 0
        bot.Remember(OpenAI_API::ShortTermMemoryPrefix, short_term_memory)
        command = "continue"
      else
        command = "prompt"
      end
    else
      command = "ambient"
    end
  end
  case command
  when "ambient"
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
when "image"
  ai = OpenAI_API.new(bot, profile,
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
  bot.Remember(OpenAI_API::ShortTermMemoryDebugPrefix + ":" + bot.thread_id, "true")
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
