#!/usr/bin/env ruby

require_relative 'xcs-base'

#output = send(*ARGV)

action = ARGV[0]
bot_name = Regexp.new ARGV[1]

case action
when "bots"
  puts get_bots[0].response.guid
end
exit

if output.is_a? DeepStruct
    puts output.to_h
elsif output.is_a? Array
    output.each do |i|
        puts i.to_h
    end
else
    puts output.to_s
end
