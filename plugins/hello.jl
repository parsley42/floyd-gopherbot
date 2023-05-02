#!/usr/bin/env julia

include(joinpath(ENV["GOPHER_INSTALLDIR"], "lib", "gopherbot_v1.jl"))
using .bot

function main()
    robot = bot.new()
    bot.Say(robot, "Hello, World!")  # Add the module name as a prefix
end

function switch(command::String)
    if command == "hello"
        main()
    end
end

if length(ARGS) > 0
    command = popfirst!(ARGS)  # Shift the first element and remove it from ARGS
    switch(command)
else
    exit(0)
end
