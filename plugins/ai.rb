#!/usr/bin/ruby

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
  - "(bot), prompt <query> - Start a new threaded conversation with OpenAI"
  - "(bot), ai <query> - Send a single query to OpenAI, generating a reply in the channel"
  - "(bot), add-token - Add your personal OpenAI token (robot will prompt you in a DM)"
  - "(bot), remove-token - Remove your personal OpenAI token"
CommandMatchers:
- Command: 'prompt'
  Regex: '(?i:(prompt|ai|query)(?:=([\w-]+))? (.*))'
- Command: 'resume'
  Regex: '(?i:(?:(?:resume|continue)[ -]conversation) (.*))'
- Command: 'token'
  Regex: '(?i:(?:link|add|set)[ -]token)'
- Command: 'rmtoken'
  Regex: '(?i:(?:rm|remove|unlink|delete|unset)[ -]token)'
ReplyMatchers:
- Label: 'continuation'
  Regex: '.*'
## n.b. - these were generated by an earlier version of this plugin
Config:
  Continuations:
  - "Do you need any further assistance?"
  - "Can I provide any more information?"
  - "What else can I do for you?"
  - "Is there anything else I can help you with?"
  - "Would you like to learn more?"
  - "Do you have any other questions?"
  - "What else do you need to know?"
  - "Can I answer any more of your questions?"
  - "Do you have any other inquiries?"
  - "Would you like me to explain something else?"
  - "Is there anything else I can explain?"
  - "What other information do you need?"
  - "Do you need more information about this topic?"
  - "Can I help you with anything else?"
## This should only be enabled in alternate configurations for the plugin,
## where `AllowDirect` is set to 'false' and only a single application
## channel is specified.
# MessageMatchers:
# - Command: 'ambient'
#   Regex: '(.*)'
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

class AIPrompt
  attr_reader :valid, :error

  TokenMemory = "usertokens"

  def initialize(bot, profile,
      init_conversation:,
      remember_conversation:,
      force_thread:,
      direct:
    )
    # We don't default the var because it could be just set to a zero-length string ("")
    unless profile and profile.length > 0
      profile = "davinci-std"
    end
    @force_thread = force_thread
    @bot = @force_thread ? bot.Threaded : bot
    @direct = direct
    @memory = @direct ? "ai-conversation" : bot.thread_id
    @profile = profile
    @exchanges = []
    @valid = true
    @remember_conversation = remember_conversation
    @init_conversation = init_conversation

    if (bot.threaded_message or @direct) and @remember_conversation and not @init_conversation
      conversation = bot.Recall(@memory)
      if conversation.length > 0
        @exchanges = decode(conversation)
      else
        unless init_conversation
          @valid = false
          @error = "Sorry, I've forgotten what we were talking about"
        end
      end
    end

    case @profile
    when "davinci-std"
      @model = "text-davinci-003"
      @temperature = 0.84      # creativity
      @max_tokens = 2212
      @max_input = 3997 - @max_tokens
      @responses = 1           # n
      @word_probability = 0.7  # top_p
      @frequency_penalty = 0.2
      @presence_penalty = 0.4
      @user_string = "Human:"
      @ai_string = "AI:"
      @max_tokens = 1001
      @max_input = 3997 - @max_tokens
      @stop = [ @user_string, @ai_string]
      @num_beams = 7           # unused?
      @initial = {
        "human" => "Who are you?",
        "ai" => "I am an AI created by OpenAI. How can I help you?"
      }
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
    prompt, tokens, truncated = build_prompt(input)
    @bot.Log(:info, "Using prompt with #{tokens} tokens; truncated: #{truncated}")
    if @bot.channel == "mock" and @bot.protocol == "terminal"
      puts("DEBUG full prompt:\n#{prompt}")
    end
    if @bot.channel == "mock"
      aitext = "Profile #{@profile} and query: #{input} in channel: #{@bot.channel}"
    else
      response = @client.completions(parameters: {
        model: @model,
        prompt: prompt,
        temperature: @temperature,
        max_tokens: @max_tokens,
        n: @responses,
        top_p: @word_probability,
        frequency_penalty: @frequency_penalty,
        presence_penalty: @presence_penalty,
        # num_beams: @num_beams,
      })
      if response["error"]
        message = response["error"]["message"]
        bot.SayThread("Sorry, there was an error - '#{message}'")
        bot.Log(:error, "connecting to openai: #{message}")
        exit(0)
      end
      aitext = response["choices"][0]["text"].lstrip
    end
    if input.length > 0
      @exchanges << {
        "human" => input,
        "ai" => aitext
      }
    end
    if @remember_conversation
      @bot.Remember(@memory, encode(@exchanges))
    end
    aitext.strip!
    return @bot, aitext
  end

  def build_prompt(input)
    initial = exchange_string(@initial)
    prompt = String.new
    final = nil
    if input.length > 0
      final = "Human: #{input}\nAI:"
    end
    exchanges = []
    @exchanges.reverse_each do |exchange|
      exchange_string = exchange_string(exchange)
      exchanges.unshift(exchange)
      prompt = exchange_string + prompt
    end
    @exchanges = exchanges
    prompt = initial + prompt
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

  def encode(array_of_hashes)
    json = array_of_hashes.to_json
    Base64.strict_encode64(json)
  end

  def decode(encoded_json)
    json = Base64.strict_decode64(encoded_json)
    JSON.parse(json)
  end

  def count_tokens(str)
    count = str.scan(/\w+|[^\s\w]+/s).length
    count += str.count("\n")
  end

  def exchange_string(exchange)
    return "#{@user_string} #{exchange["human"]}\n#{@ai_string} #{exchange["ai"]}\n"
  end
end

direct = (bot.channel == "")
ambient = (command == "ambient")

case command
when "ambient", "prompt", "ai", "resume"
  init_conversation = false
  remember_conversation = true
  force_thread = false
  if command == "prompt"
    ## See the regex - we match and use the verb
    command = ARGV.shift
    command = "prompt" if command == "query"
  end
  if direct and command == "ai"
    command = "prompt"
  end
  case command
  when "ambient"
    init_conversation = true unless bot.threaded_message
    force_thread = true
  when "ai"
    init_conversation = true
    remember_conversation = false
  when "prompt"
    init_conversation = true
    force_thread = true unless direct
  when "resume"
    unless direct or bot.threaded_message
      bot.SayThread("Sorry, you can't resume AI conversations in a channel")
      exit(0)
    end
    init_conversation = false
  end
  if command == "ambient" or command == "resume"
    profile = ""
    prompt = ARGV.shift
  else
    profile, prompt = ARGV.shift(2)
  end
  ai = AIPrompt.new(bot, profile,
    init_conversation: init_conversation,
    remember_conversation: remember_conversation,
    force_thread: force_thread,
    direct: direct
  )
  unless ai.valid
    bot.SayThread(ai.error)
    exit(0)
  end
  if init_conversation
    bot.SayThread("(please wait while I contact the AI)")
  end
  aibot, reply = ai.query(prompt)
  if remember_conversation and (direct or not ambient)
    continuations = bot.GetTaskConfig()["Continuations"]
    ending = " ('quit' to finish)"
    while true
      prompt = String.new
      if reply.end_with?("?")
        prompt = reply + ending
      else
        aibot.Say(reply)
        prompt = aibot.RandomString(continuations) + ending
      end
      rep = aibot.PromptForReply("continuation", prompt)
      unless rep.ret == Robot::Ok
        aibot.Say("(use 'resume conversation <query>' to continue)")
        break
      end
      if rep.reply == "quit"
        aibot.Say("(use 'resume conversation <query>' if you want to continue)")
        break
      end
      aibot, reply = ai.query(rep.reply)
    end
  else
    aibot.Say(reply)
  end
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
