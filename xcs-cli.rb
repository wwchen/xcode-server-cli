#!/usr/bin/env ruby

require_relative 'xcs'

#output = send(*ARGV)

if ARGV.count < 1
  puts "Usage: ./xcs-cli.rb (status|run|bot-config|cancel-pending|stop) [args]"
  puts "Regex is supported for bot name"
  exit
end

action = ARGV[0]
branch_name = ARGV[1]
bot_name = ARGV[2]
scheme_name = ARGV[3]
bot_ids = XCodeInteractive.find_bot_ids_by_scm_info branch_name, bot_name

case action
when "status"
    XCodeInteractive.print_bots
when "bot-config"
    bot_ids.each do |bot_id|
        XCodeInteractive.print_bot_configuration bot_id
    end
when "run"
    bot_ids.each do |bot_id|
        XCodeInteractive.integrate_bot bot_id
    end
when "cancel-pending"
    bot_ids.each do |bot_id|
        XCodeAPIInterface.cancel_pending_integrations_for_bot_id bot_id
    end
when "stop"
    bot_ids.each do |bot_id|
        XCodeInteractive.stop_integrations_for_bot_id bot_id
    end
end
