#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'ostruct'
require 'date'

SESSION_GUID = "083e62d0-ebf3-4608-a463-79446c785b72"
#URL = URI 'http://iceiosbuild.redmond.corp.microsoft.com/xcs/svc'
URL = URI 'http://localhost/xcs/svc'
DEBUG = false
VERBOSE = true
YES = "✔"
NO = "✘"

def get_response (uri, body)
    headers = { 'content-type' => 'application/json; charset=UTF-8', 'accept' => 'application/json' }
    http = Net::HTTP.new uri.hostname
    if DEBUG
        puts JSON.pretty_generate(body)
    end
    resp = http.put(uri, body.to_json, headers)
    return JSON.parse(resp.body)
end

def service_request (service_name, method_name, arguments)
    json = {
        :type        => "com.apple.ServiceRequest",
        :arguments   => arguments, #[ "c631ef65-53b9-53b9-a34b-533001fbbec2", "10" ],
        :sessionGUID => SESSION_GUID,
        :serviceName => service_name, #"XCBotService",
        :methodName  => method_name, #"botRunForBotGUID:andIntegrationNumber:",
        :expandReferencedObjects => false
    }
    response = DeepStruct.new get_response(URL, json)
    raise ArgumentError, "Bad response: #{response}" unless response.succeeded
    raise ArgumentError, "Not found: #{response}" if response.response and response.response.reason == "not-found"
    return response
end


##
# Actions
##
def cancel_botrun (bot_guid)
    args = [ bot_guid ]
    resp = service_request("XCBotService", "cancelBotRunWithGUID:", args)
    printf "Cancel botrun with guid: %s --> %s\n", botrun_guid, resp.responseStatus
    return resp
end

# NOTE: limitation on API
def clear_queued_botruns (bot_guid)
    botruns  = get_botruns(bot_guid)
    botruns.each do |botrun|
        printf "%s) %s - %s\n", botrun.integration, botrun.status, botrun.guid
    end
    
    return
end

def schedule_botrun (bot_guid)
    args = [ bot_guid ]
    resp = service_request("XCBotService", "startBotRunForBotGUID:", args)
    printf "Scheduled botrun with guid: %s --> %s\n", bot_guid, resp.responseStatus
    return resp
end

def create_bot (args)
    args = DeepStruct.new({
        :guid => "c6345aa8-871b-871b-ce3d-809252ddc859",
        :shortName => "buildchecker",
        :longName => "Build Checker",
        :extendedAttributes => {
            :scmInfo => {
                :/ => { :scmBranch => "main" }
            },
            :scmInfoGUIDMap => {
                :/ => "878372f8-4059-a7bc-56a8-84dcbc67c1a6"
            },
            :buildProjectPath => "common/TFSSync/TFSSync/TFSSync.xcodeproj",
            :buildSchemeName => "CIBuildCheck",
            :pollForSCMChanges => false,
            :buildOnTrigger => false,
            :buildFromClean => 0,
            :integratePerformsAnalyze => false,
            :integratePerformsTest => false,
            :integratePerformsArchive => false,
            :deviceSpecification => null,
            :deviceInfo => [ ]
        },
        :notifyCommitterOnSuccess => false,
        :notifyCommitterOnFailure => false,
        :type => "com.apple.entity.Bot"
    })
end

##
# Query responses
##
def get_botrun (bot_guid, integration_no = nil)
    if integration_no
        args = [ bot_guid, integration_no ]
        resp = service_request("XCBotService", "botRunForBotGUID:andIntegrationNumber:", args)
        return resp
    else
        args = [ bot_guid ]
        resp = service_request("XCBotService", "latestTerminalBotRunForBotGUID:", args)
        return resp
    end
end

def get_bot (bot_guid)
    args = [ bot_guid ]
    resp = service_request("XCBotService", "botForGUID:", args)
    return resp

    # prettify
    if resp.succeeded
        # TODO
    end
end

def get_entity (guid)
    args = [ guid ]
    return service_request("ContentService", "entityForGUID:", args)
end

def get_bots ()
    # query for the raw data
    args = [
        { 
            :query       => nil,
            :fields      => [ "tinyID", "longName", "shortName", "type", "createTime", "updateTime", "isDeleted", "tags", "description" ],
            :subFields   => { },
            :sortFields  => [ "+longName" ],
            :entityTypes => [ "com.apple.entity.Bot" ],
            :onlyDeleted => false
        }
    ]
    response = service_request("SearchService", "query:", args)

    bots = Array.new
    if response.succeeded
        results = response.response.results.map { |b| b.entity }
        results.sort_by! { |b| b.lastActivityTime.epochValue } # b.longName
        results.each { |b| bots.push(get_bot(b.guid)) }
    end
    return bots
end


def get_botruns (bot_guid, limit = 25)
    # query for the raw data
    args = [ 
        :query => {
            :and => [ # :or supported
                {
                    :match => "com.apple.entity.BotRun",
                    :field => "type",
                    :exact => true,
                },
                {
                    :match => bot_guid,
                    :field => "ownerGUID",
                    :exact => true
                }
            ],
        },
        :fields => [ "tinyID", "longName", "shortName", "type", "createTime", "startTime", "endTime", "status", "subStatus", "integration" ],
        :range => [0, limit],
        :onlyDeleted => false
    ]
    return service_request("SearchService", "query:", args)
end


##
# Helper get methods
##
def get_bot_name (bot_guid)
    return get_entity(bot_guid).response.longName.sstrip
end

def execution_time (dt_object_start, dt_object_end)
    if dt_object_start
        start_time = dt_object_start.epochValue.to_f
        timestamp = start_time.to_date("%m/%d/%y %H:%M")
        if dt_object_end
            end_time = dt_object_end.epochValue.to_f
            timestamp = sprintf "%s - %s (%i mins)", timestamp, end_time.to_date("%H:%M"), ((end_time - start_time) / 60).to_i
        end
        return timestamp
    end
end

##
# Get pretty info
##

def print_botruns (bot_guid, limit = 25)
    response = get_botruns(bot_guid, limit)
    puts response.to_h if DEBUG

    integrations = Array.new
    if response.succeeded
        puts "-" * 20
        printf "Bot runs for %s\n", get_bot_name(bot_guid)
        results = response.response.results.sort_by { |b| b.entity.integration }
        results.each_with_index do |result, i|
            puts result.to_h if DEBUG
            entity = result.entity
            column = Array.new
            column.push(sprintf "%-2s", i+1)
            column.push(sprintf " %-7s", "Int#{entity.integration}")
            column.push(sprintf "%-20s", "#{entity.status} (#{entity.substatus})")
            column.push(sprintf "%-40s", execution_time(entity.startTime, entity.endTime))
            if VERBOSE
                column.push(entity.guid)
            end
            integrations.push(entity.integration)
            puts column.join
        end
        puts "-" * 20
    end
    return integrations
end

def print_botrun (bot_guid, integration_no = nil)
    response = get_botrun(bot_guid, integration_no)
    puts response.to_h if DEBUG

    title = ""
    if integration_no
        title = sprintf "Bot run (%i) for %s\n", integration_no, get_bot_name(bot_guid)
    else
        title = sprintf "Latest bot run for %s\n", get_bot_name(bot_guid)
    end

    if response.succeeded
        puts "-" * 20, title
        # puts response.to_h
        attr = response.response.extendedAttributes
        build_output = attr.output.build if attr.output

        errors       = build_output.ErrorSummaries
        warnings     = build_output.WarningSummaries
        actions      = build_output.Actions
        archive_path = build_output.ArchivePath
        is_running  = build_output.Running
        analyzer_warnings = build_output.AnalyzerWarningSummaries

        if errors
            puts "Errors:"
            errors.each do |error|
                puts error.to_h if DEBUG
                printf "  %s (%s): %s\n", error.IssueType, error.Target, error.Message
            end
            puts '-' * 10
        end

        if warnings
            puts "Warnings:"
            warnings.each do |error|
                puts error.to_h if DEBUG
                printf "  %s (%s): %s\n", error.IssueType, error.Target, error.Message
            end
            puts '-' * 10
        end

        if analyzer_warnings
            puts "Analyzer Warnings:"
            analyzer_warnings.each do |error|
                puts error.to_h if DEBUG
                printf "  %s (%s): %s\n", error.IssueType, error.Target, error.Message
            end
            puts '-' * 10
        end

        if actions
            puts "Actions:"
            actions.each do |action|
                #puts action.to_h 
                printf " %s (%s): %s\n", action.Title, action.SchemeCommand, execution_time(action.StartedTime, action.EndedTime)
                # BuildResult.AnalyzerWarningSummaries, RunDestination.{TargetArchitecture, Name, TargetDevice, TargetSDK}
            end
        end

        #puts errors, actions, archive_path, is_running, analyzer_warnings

        title = sprintf "%s (%s)\n", attr.longName, attr.guid
        printf "%s\n%s\n", title, "=" * title.length
        puts "-" * 20
    end
end

## 
# Class overload
##

# http://andreapavoni.com/blog/2013/4/create-recursive-openstruct-from-a-ruby-hash/#.U6z4xY1g5vk
class DeepStruct < OpenStruct
    def initialize(object=nil)
        @table = {}
        @hash_table = {}
        if object.is_a?(Hash)
            object.each do |k,v|
                if v.is_a?(Array)
                    v.map! { |e| self.class.new(e) }
                end
                @table[k.to_sym] = (v.is_a?(Hash) ? self.class.new(v) : v)
                @hash_table[k.to_sym] = v
                new_ostruct_member(k)
            end
        end
    end

    def to_h
        JSON.pretty_generate @hash_table
    end
end

class String
    def sstrip
        self.tr(" ", " ").strip
    end
end

class Float
    def to_date (format = "%m/%d/%y %H:%M")
        DateTime.strptime(self.to_s, "%s").strftime(format)
    end
end


##
# main
##

newspreci = "c6330605-5f48-5f48-68f1-7a015814973e"
axpci = "c631e5f9-9f1c-9f1c-288f-1c917f4612c5"
yumci = "c631e891-11d2-11d2-204c-f489aa41cf47"
travelstable = "c631ef81-1be0-1be0-a770-1aabbbb77311"

#puts clear_queued_botruns yumci
#cancel_bot "0812e43f-b9d3-4348-b49d-dab2f781ea2b"
#print_bots
#print_botruns travelstable
#print_botrun axpci

#puts JSON.pretty_generate put(uri, test)


# retrieve commits
'{
  "type": "com.apple.BatchServiceRequest",
  "requests": [
    {
      "type": "com.apple.ServiceRequest",
      "arguments": [
        "$result->{responses}[0]->{response}->{guid}"
      ],
      "sessionGUID": "30ea7c14-49fb-497e-9999-4a9d2bef1f60",
      "serviceName": "XCBotService",
      "methodName": "scmCommitsForBotRunGUID:",
      "expandReferencedObjects": false
    }
  ]
}'

# status
#"methodName": "latestBotRunForBotGUID:",

# last-status
#"methodName": "latestTerminalBotRunForBotGUID:",

# context
#"methodName": "metaTagsForEntityID:withRoute:",
#
