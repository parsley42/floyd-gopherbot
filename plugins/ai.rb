#!/usr/bin/ruby

# load the Gopherbot ruby library and instantiate the bot
require 'gopherbot_v1'
bot = Robot.new()

command = ARGV.shift()

defaultConfig = <<'DEFCONFIG'
---
Channels:
- ai
AllowDirect: false
Help:
- Keywords: [ "ai", "prompt", "query", "token" ]
  Helptext:
  - "(bot), prompt <query> - Send a query to the OpenAI LLM"
  - "(bot), add-token - Add your personal OpenAI token (robot will prompt you in a DM)"
  - "<query> - Send a query to the OpenAI LLM (all messages)"
CommandMatchers:
- Command: 'prompt'
  Regex: '(?i:(?:prompt|query)(?:=([\w-]+))? (.*))'
- Command: 'token'
  Regex: '(?i:(?:link|add|set)[ -]token)'
MessageMatchers:
- Command: 'ambient'
  Regex: '(.*)'
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
  attr_reader :authenticated

  TokenMemory = "usertokens"

  def initialize(bot, profile)
    # We don't default the var because it could be just set to a zero-length string ("")
    unless profile and profile.length > 0
      profile = "davinci-std"
    end
    @bot = bot.Threaded
    @profile = profile
    @exchanges = []
    if bot.threaded_message
      conversation = bot.Recall(bot.thread_id)
      if conversation.length > 0
        @exchanges = decode(conversation)
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
    token = get_token()
    if token and token.length > 0
      @authenticated = true
    else
      @authenticated = false
    end
    Ruby::OpenAI.configure do |config|
      config.access_token = token
      # config.organization_id = ENV.fetch('OPENAI_ORGANIZATION_ID') # Optional.
    end
    @client = OpenAI::Client.new
  end

  def get_token
    token = nil
    token_memory = @bot.CheckoutDatum(TokenMemory, false)
    if token_memory.exists
      token = token_memory.datum[@bot.user]
      @bot.Log(:info, "Using personal token for #{@bot.user}") if token
    end
    unless token
      token = ENV['OPENAI_KEY']
      @bot.Log(:info, "Using global token for #{@bot.user}") if token
    end
    @bot.Log(:error, "No OpenAI token found for request from user #{@bot.user}")
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

  def build_prompt(input)
    initial = exchange_string(@initial)
    prompt = String.new
    final = nil
    truncated = false
    current_length = count_tokens(initial)
    if input.length > 0
      final = "Human: #{input}\nAI:"
      current_length += count_tokens(final)
    end
    exchanges = []
    @exchanges.reverse_each do |exchange|
      exchange_string = exchange_string(exchange)
      size = count_tokens(exchange_string)
      if current_length + size > @max_input
        truncated = true
        break
      end
      exchanges.unshift(exchange)
      current_length += size
      prompt = exchange_string + prompt
    end
    @exchanges = exchanges
    prompt = initial + prompt
    if final
      prompt += final
    end
    return prompt, current_length, truncated
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
      aitext = response["choices"][0]["text"].lstrip
    end
    if input.length > 0
      @exchanges << {
        "human" => input,
        "ai" => aitext
      }
    end
    @bot.Remember(@bot.thread_id, encode(@exchanges))
    @bot.Say(aitext)
  end
end

case command
when "ambient", "prompt"
  if command == "ambient"
    profile = ""
    prompt = ARGV.shift
  else
    profile, prompt = ARGV.shift(2)
  end
  ai = AIPrompt.new(bot, profile)
  unless ai.authenticated
    botalias = bot.GetBotAttribute("alias")
    bot.SayThread("Sorry, you need to add your token first - try '#{botalias}help'")
    exit(0)
  end
  unless bot.threaded_message
    bot.SayThread("(please hold while I ask the AI)")
  end
  ai.query(prompt)
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
end
