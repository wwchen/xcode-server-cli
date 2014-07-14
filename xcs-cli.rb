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
    bot = Bot.new bot
    printf "%-30s %s\n", bot.name, bot.latest_run_status
  end
when "run"
  bots.each do |bot|
    bot = Bot.new bot
    schedule_botrun bot.guid
  end
end
