#!/usr/bin/env ruby

require_relative 'xbot'

output = send(*ARGV)

if output.is_a? DeepStruct
    puts output.to_h
elsif output.is_a? Array
    output.each do |i|
        puts i.to_h
    end
else
    puts output.to_s
end
