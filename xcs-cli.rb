#!/usr/bin/env ruby

require_relative 'xcs'

#output = send(*ARGV)

if ARGV.count < 1
  puts "Usage: ./xcs-cli.rb (status|run|bot-config|cancel) [args]"
  puts "Regex is supported for bot name"
  exit
end

action = ARGV[0]

case action
when "status"
    XCodeInteractive.print_bots
when "bot-config"
    bot_name = ARGV[1]
    bot_ids = XCodeInteractive.find_bot_ids_by_name bot_name
    bot_ids.each do |bot_id|
        XCodeInteractive.print_bot_configuration bot_id
    end
when "run"
    bot_name = ARGV[1]
    bot_ids = XCodeInteractive.find_bot_ids_by_name bot_name
    bot_ids.each do |bot_id|
        XCodeInteractive.integrate_bot bot_id
    end
when "cancel"
    integration_id = ARGV[1]
    interface.cancel_integration integration_id
end
