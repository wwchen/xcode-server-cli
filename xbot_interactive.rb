#!/usr/bin/env ruby

require_relative 'xbot'
require 'json'
require 'date'

def read_number (prompt, max = 10000)
    valid = false
    input = ""
    while not valid
        printf "%s: ", prompt
        input = $stdin.readline.strip
        valid = (!/^[0-9]+$/.match(input).nil?) && input.to_i > 0 && input.to_i <= max
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

short_hostname = HOSTNAME.sub(/\..*/, '').upcase
while true
    printf "%s Xcode Server (%s) Status at %s %s\n", "="*10, short_hostname, DateTime.now.strftime("%m/%d/%y %H:%M"), "="*10
    bots = print_bots

    def prompt
        printf "%s Actions %s\n", "="*10, "="*10
        puts "1. Schedule a build run"
        puts "2. Look into details of a build run"
        puts "3. Refresh"
        puts "4. Quit"
    end
    prompt
    case read_number "Choice of action", 4
    when 1
        selection = read_number("Select which bot to schedule", bots.length+1)
        bot_guid  = bots[selection-1]
        schedule_botrun(bot_guid).to_h
    when 2
        selection = read_number("Select which bot to look into", bots.length+1)
        bot_guid  = bots[selection-1]
        integrations = print_botruns(bot_guid)
        selection = read_number "Select which bot run to look into", integrations.length
        print_botrun(bot_guid, integrations[selection-1])
    when 3
        next
    when 4
        puts "Thanks for using. Questions or comments, email axpiosadmin@microsoft.com"
        exit
    end
    printf "Press any key to continue.. "
    $stdin.readline
end

