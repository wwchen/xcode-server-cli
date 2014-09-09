#!/usr/bin/env ruby

require_relative 'xcs-base'

#output = send(*ARGV)

if ARGV.count < 2
  puts "Usage: ./xcs-cli.rb (status|run) [bot name]"
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
    print_botrun bot.guid
  end
when "run"
  bots.each do |bot|
    bot = Bot.new bot
    puts bot.integrate
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
end
