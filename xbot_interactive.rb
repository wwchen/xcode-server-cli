#!/usr/bin/env ruby

require_relative 'xbot'
require 'json'

def read_number (prompt)
    valid = false
    input = ""
    while not valid
        printf "%s: ", prompt
        input = $stdin.readline.strip
        valid = /^[0-9]+$/.match(input)
        puts "Invalid input!" unless valid
    end
    return input.to_i
end

def print_bots()
    bots = get_bots()
    bots.each_with_index do |bot, i|
        next if bot.isDeleted or not bot.succeeded
        bot = bot.response
        column = Array.new
        column.push(i+1)
        column.push(bot.longName.sstrip)
        column.push(sprintf "%s (%s)", bot.latestRunStatus, bot.latestRunSubStatus)
        column.push(bot.lastActivityTime.epochValue.to_date)
        if VERBOSE
            column.push(bot.guid)
            printf("%2s. %-25s %-30s %-20s %s\n", *column)
        else
            printf("%2s. %-25s %-30s %s\n", *column)
        end
    end
    return bots.map { |b| b.response.guid }
end

$config = {
    :sessionGuid => "083e62d0-ebf3-4608-a463-79446c785b72",
}

if DEBUG
    puts "======= DEBUG ======="
    puts JSON.pretty_generate JSON.parse $config
    puts "====================="
end

printf "%s Xcode Server Status %s\n", "="*10, "="*10
bots = print_bots
selection = read_number "Select which bot to look into"
bot_guid = bots[selection-1]
integrations = print_botruns(bot_guid)
selection = read_number "Select which bot run to look into"
print_botrun(bot_guid, integrations[selection-1])

