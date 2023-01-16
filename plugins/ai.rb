#!/usr/bin/ruby

# load the Gopherbot ruby library and instantiate the bot
require 'gopherbot_v1'
bot = Robot.new()

command = ARGV.shift()

case command
when "init"
  system("gem install --user-install --no-document ruby-openai")
  exit(0)
when "configure"
  exit(0)
end

defaultConfig = <<'DEFCONFIG'
MessageMatchers:
- Command: chuck
  Regex: '(?i:chuck norris)'
Config:
  Openings:
  - "Chuck Norris?!?! He's AWESOME!!!"
  - "Oh cool, you like Chuck Norris, too?"
  - "Speaking of Chuck Norris - "
  - "Hey, I know EVERYTHING about Chuck Norris!"
  - "I'm a HUUUUGE Chuck Norris fan!"
  - "Not meaning to eavesdrop or anything, but are we talking about CHUCK NORRIS ?!?"
  - "Oh yeah, Chuck Norris! The man, the myth, the legend."
DEFCONFIG

require "ruby/openai"

class AIPrompt
    def initialize(bot, profile)
        # We don't default the var because it could be just set to a zero-length string ("")
        unless profile and profile.length > 0
            profile = "davinci-std"
        end
        @bot = bot
        @profile = profile
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
            @num_beams = 7           # unused?
        end
        Ruby::OpenAI.configure do |config|
            config.access_token = ENV.fetch('OPENAI_KEY')
            # config.organization_id = ENV.fetch('OPENAI_ORGANIZATION_ID') # Optional.
        end
        @client = OpenAI::Client.new
    end

    def query(input)
        aitext = "Profile #{@profile} and query: #{input} with key: #{ENV["OPENAI_KEY"]}"
        # response = @client.completions(parameters: {
        #     model: @model,
        #     prompt: input,
        #     temperature: @temperature,
        #     max_tokens: @max_tokens,
        #     n: @responses,
        #     top_p: @word_probability,
        #     frequency_penalty: @frequency_penalty,
        #     presence_penalty: @presence_penalty,
        #     # num_beams: @num_beams,
        # })
        # # pp(response)
        # aitext = response["choices"][0]["text"].lstrip
        require "debug/open"
        @bot.Say(aitext)
    end
end

case command
when "prompt"
    profile, prompt = ARGV.shift(2)
    ai = AIPrompt.new(bot.Threaded, profile)
    ai.query(prompt)
end
