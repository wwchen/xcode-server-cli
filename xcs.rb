#!/usr/bin/env ruby

require_relative 'xcs-base'

#output = send(*ARGV)

if ARGV.count < 2
  puts "Usage: ./xcs-cli.rb (status|run|update-branch|cancel) [bot name] [additional args]"
  puts "Regex is supported for bot name"
  exit
end

action = ARGV[0]
bot_name = Regexp.new ARGV[1], Regexp::IGNORECASE
bots = get_bots.keep_if { |b| b.longName =~ bot_name }

#bots.each { |b| prints "%s %s\n", b.longName, b.guid }

case action
when "status"
  bots.each do |bot|
    printf "%-30s %s\n", bot.name, bot.latest_run_status
    bot.botruns.last.to_s
  end
when "run"
  bots.each do |bot|
    response = bot.integrate
    printf "Scheduled botrun for %s\n", bot.name
    printf "Integration queued is %s\n", response.integration
  end
when "create-test"
  options = {
    "name" => "test",
    "buildProjectPath" => "common/AXPlatformTest/AXPlatformTest.xcodeproj",
    "buildSchemeName" => "CI Build",
    "scmBranch" => "main",
    "scmGUID" => "2ded7b82-44b1-b7d0-4ca8-15a6a266c7f1"
  }
  printf "%s\n", Bot.new(options).to_h
when "update-branch"
    branch_name = ARGV[2]
    bots.each do |bot|
        options = { "branch" => branch_name }
        bot.update options
    end
when "cancel"
    # TODO wichen: I think it's a little buggy. Doens't always work
    bot_names = bots.map { |b| b.name }
    puts "Canceling #{bot_names} until script is interrupted\n"
    while true
        bots.each do |bot|
            status = bot.latestRunStatus
            if status =~ /(running|integrating)/
                printf "%s is running. Canceling...\n", bot.name
                bot.cancel
            elsif status =~ /(completed|canceled)/
            else
                printf "%s: %s\n", bot.name, status
            end
        end

        sleep 2
    end
end
