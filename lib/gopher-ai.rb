require "openai"
require 'json'
require 'base64'
require 'digest/sha1'

class ConversationStatus
  attr_accessor :valid, :error, :tokens
  def initialize(valid, error, tokens)
    @valid = valid
    @error = error
    @tokens = tokens
  end
end

class OpenAI_API
  attr_reader :status, :cfg

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
    @tokens = 0
    @valid = true
    @remember_conversation = remember_conversation
    @init_conversation = init_conversation
    debug_memory = @bot.Recall(ShortTermMemoryDebugPrefix + ":" + bot.thread_id)
    @debug = (debug_memory.length > 0 or debug)

    error = nil
    if (bot.threaded_message or @direct) and @remember_conversation and not @init_conversation
      encoded_state = bot.Recall(@memory)
      state = decode_state(encoded_state)
      profile, @tokens, exchanges = state.values_at("profile", "tokens", "exchanges")
      if exchanges.length > 0
        @exchanges = exchanges
        @profile = profile
      else
        unless init_conversation
          @valid = false
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
      error = "Sorry, you need to add your token first - try '#{botalias}help'"
    end
    if @valid
      OpenAI.configure do |config|
        config.access_token = token
        if @org
          config.organization_id = @org
        end
      end
      @client = OpenAI::Client.new
    end
    @status = ConversationStatus.new(@valid, error, @tokens)
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
      @tokens = usage["total_tokens"]
      if @tokens > @max_context
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
      "tokens": @tokens,
      "exchanges": @exchanges
    }
    json = state.to_json
    Base64.strict_encode64(json)
  end

  def decode_state(encoded_state)
    unless encoded_state and encoded_state.length > 0
      return {
        "profile" => "",
        "tokens": 0,
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
