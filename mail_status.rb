#!/usr/bin/env ruby

require_relative 'xcs-base'
require 'mail'

FROM = "admin@iceiosbuild.redmond.corp.microsoft.com"

if ARGV.length < 3
    puts "Usage: ./mail_build_status.rb <bot_guid> <to_email> <cc_email>"
    exit
end

bot_guid = ARGV[0]
to = ARGV[1].gsub(/"/, '').gsub(/,/, ';')
cc = ARGV[2].gsub(/"/, '').gsub(/,/, ';')

Mail.defaults do
    delivery_method :sendmail
end

botrun = Bot.new(bot_guid).botrun

puts botrun.class
if botrun
    build_output = botrun.extendedAttributes.output.build 

    name        = botrun.extendedAttributes.botSnapshot.longName.sstrip
    error       = build_output.ErrorSummaries
    warning     = build_output.WarningSummaries
    issue       = build_output.AnalyzerWarningSummaries
    error_cnt   = build_output.ErrorCount
    warning_cnt = build_output.WarningCount
    issue_cnt   = build_output.AnalyzerWarningCount
    archive_path = build_output.ArchivePath
    is_running   = build_output.Running
    commits      = botrun.scmCommitGUIDs

    unless error_cnt == 0 and warning_cnt == 0 and issue_cnt == 0
        puts "Preparing email"

        inline_summary = Array.new
        inline_summary.push "#{error_cnt} errors"     if error_cnt > 0
        inline_summary.push "#{warning_cnt} warnings" if warning_cnt > 0
        inline_summary.push "#{issue_cnt} issues"     if issue_cnt > 0
        subject = "#{name.split.first} build status: #{inline_summary.join(', ')}"
        body = Array.new

        summary_table = Array.new
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Name", name
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Integration", botrun.integration
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Status", botrun.status
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Substatus", botrun.subStatus
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Execution time", execution_time(botrun.startTime, botrun.endTime)
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Error count", error_cnt
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Warning count", warning_cnt
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Analysis issues", issue_cnt
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Test count", build_output.TestsCount
        summary_table.push sprintf "<tr><td>%s </td><td>%s</td></tr>", "Test failures", build_output.TestsFailedCount
        summary_table = sprintf "<table>%s</table>", summary_table.join

        body.push "#{name} has been built. Below are errors, warnings, and issues encountered during the build"
        body.push "<h1>Summary</h1>"
        body.push summary_table
        body.push "<h1>Details</h1>"
        if error
            body.push "<h2>Errors</h2>"
            error.each do |error|
                body.push sprintf "  <i>%s (%s)</i>: %s\n", error.IssueType, error.Target, error.Message
            end
        end
        if warning
            body.push "<h2>Warnings</h2>"
            warning.each do |error|
                body.push sprintf "  <i>%s (%s)</i>: %s\n", error.IssueType, error.Target, error.Message
            end
        end
        if issue
            body.push "<h2>Analysis Issues</h2>"
            issue.each do |error|
                body.push sprintf "  <i>%s (%s)</i>: %s\n", error.IssueType, error.Target, error.Message
            end
        end

        unless commits.nil? or commits.empty? 
            body.push "<h1>Commits</h1>"
            commit_table = Array.new
            commit_table.push "<table>"
            commits.each do |commit|
                commit_rsp = get_entity(commit.to_h)
                commit_table.push "<tr><td>#{commit_rsp.commitID[-7..-1]}</td><td>#{commit_rsp.message}</td></tr>"
            end
            commit_table.push "</table>"
            body.push commit_table.join
        end
        


        Mail.deliver do
            from FROM
              to to
              cc cc
            subject subject
            html_part do
                content_type 'text/html; charset=UTF=8'
                #body body.map { |l| if l.match />$/ then l + "<br>" else l end }.join 
                body body.join "<br>"
            end
        end
        #puts "Mail delievered to #{info["to"]}, cc #{info["cc"]}"
        puts "Mail delievered"
    end
end
