#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'ostruct'

SESSION_GUID = "083e62d0-ebf3-4608-a463-79446c785b72"
HOSTNAME = "iceiosbuild.redmond.corp.microsoft.com"
DEBUG = false
VERBOSE = true
CHECKMARK = "✔"
CROSSMARK = "✘"

## Makes the PUT request to call Xcode apache/collabd/sprocket's REST API
def get_response (hostname, body)
    url = URI "http://#{hostname}/xcs/svc"
    headers = { 'content-type' => 'application/json; charset=UTF-8', 'accept' => 'application/json' }
    http = Net::HTTP.new hostname
    if DEBUG
        puts JSON.pretty_generate(body)
    end
    resp = http.put(url, body.to_json, headers)
    return JSON.parse(resp.body)
end

## Prepare and send out a ServiceRequest 
def service_request (service_name, method_name, arguments)
    json = {
        :type        => "com.apple.ServiceRequest",
        :arguments   => arguments, #[ "c631ef65-53b9-53b9-a34b-533001fbbec2", "10" ],
        :sessionGUID => SESSION_GUID,
        :serviceName => service_name, #"XCBotService",
        :methodName  => method_name, #"botRunForBotGUID:andIntegrationNumber:",
        :expandReferencedObjects => false
    }
    response = DeepStruct.new get_response(HOSTNAME, json)
    raise ArgumentError, "Bad response: #{response}" unless response.succeeded
    raise ArgumentError, "Not found: #{response}" if response.response && response.response.reason == "not-found"
    return response.response
end


##
# Actions
##
def cancel_botrun (bot_guid)
    args = [ bot_guid ]
    resp = service_request("XCBotService", "cancelBotRunWithGUID:", args)
    printf "Cancel botrun with guid: %s\n", botrun_guid
    return resp
end

# NOTE: limitation on API. Doesn't actually work
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
    printf "Scheduled botrun for %s\n", get_bot_name(bot_guid)
    printf "Integration queued is %s\n", resp.integration
    return resp
end

def create_bot (options)
    # required fields
    options = DeepStruct.new options
    return unless options.name and
                  options.buildProjectPath and
                  options.buildSchemeName and
                  options.scmBranch and
                  options.scmGUID
    args = {
        #"guid" => "c6345aa8-871b-871b-ce3d-809252ddc859",
        #"shortName" => "buildchecker",
        "longName" => options.name,
        "extendedAttributes" => {
            "scmInfo" => {
                "/" => { "scmBranch" => options.scmBranch }
            },
            "scmInfoGUIDMap" => {
                "/" => options.scmGUID
            },
            "buildProjectPath"  => options.buildProjectPath,
            "buildSchemeName"   => options.buildSchemeName,
            "pollForSCMChanges" => options.pollForSCMChanges || false,
            "buildOnTrigger"    => options.buildOnTrigger || false,
            "buildFromClean"    => options.buildFromClean || 0,
            "integratePerformsAnalyze" => options.integratePerformsAnalyze || false,
            "integratePerformsTest"    => options.integratePerformsTest || false,
            "integratePerformsArchive" => options.integratePerformsArchive || false,
            "deviceSpecification" => options.deviceSpec || "specificDevices",
            "deviceInfo"          => options.deviceInfo || [
                # TODO hardcoded for now
                # "79176943-8321-4ced-a333-5059a0719b90", # iPad 7.1
                # "bc2fb07c-4217-4623-a43a-6943d53b7194", # iPad Retina 7.1
                "dba14db8-77eb-4565-9c57-b36f25c6801b", # iPad Retina (64-bit) 7.1
                # "cdb4362a-8c3e-4527-8f1b-54bca9cd44cf", # iPhone Retina (3.5-inch) 7.1
                # "2b815333-b2de-4fd0-b2b5-9ce89b8f26ce", # iPhone Retina (4-inch 64-bit) 7.1
                "fd887b68-6673-4b3a-89fa-eb9ac7e8cf43"  # iPhone Retina (4-inch) 7.1
            ]
        },
        "notifyCommitterOnSuccess" => options.notifyCommitterOnSuccess || false,
        "notifyCommitterOnFailure" => options.notifyCommitterOnFailure || false,
        "type" => "com.apple.entity.Bot"
    }

    # TODO also need to send updateEmailSubscriptionList:forEntityGUID:withNotificationType:
    # and deleteWorkScheduleWithEntityGUID:
    return service_request("XCBotService", "createBotWithProperties:", [ args ])
end

def change_bot_settings (bot_guid, options)
    # TODO also need to send updateEmailSubscriptionList:forEntityGUID:withNotificationType:
    # and deleteWorkScheduleWithEntityGUID:
    options = DeepStruct.new options

    info = get_bot(bot_guid)
    args = {
        "type" => "com.apple.EntityChangeSet",
        "changes" => [
            [
                "longName", options.name || info.longName
            ], 
            [
                "extendedAttributes",
                {
                    "buildFromClean" => options.buildFromClean || info.extendedAttributes.buildFromClean,
                    "buildOnTrigger" => options.buildOnTrigger || info.extendedAttributes.buildOnTrigger,
                    "deviceInfo"     => options.deviceInfo || info.extendedAttributes.deviceInfo.map { |a| a.to_h },
                    "deviceSpecification" => options.deviceType || info.extendedAttributes.deviceSpecification,
                    "buildProjectPath" => options.buildPath || info.extendedAttributes.buildProjectPath,
                    "pollForSCMChanges" => options.pollForChanges || info.extendedAttributes.pollForSCMChanges,
                    "scmInfoGUIDMap" => {
                        "/" => info.extendedAttributes.scmInfoGUIDMap./
                    },
                    "integratePerformsTest" => options.integratePerformsTest || info.extendedAttributes.integratePerformsTest,
                    "integratePerformsAnalyze" => options.integratePerformsAnalyze || info.extendedAttributes.integratePerformsAnalyze,
                    "integratePerformsArchive" => options.integratePerformsArchive || info.extendedAttributes.integratePerformsArchive,
                    "lastBuildFromCleanTime" => info.extendedAttributes.lastBuildFromCleanTime.to_h,
                    "lastBuildFromCleanTime" =>  {
                        "type" => "com.apple.DateTime",
                        "isoValue" => "2014-07-01T06:05:15.396-0700",
                        "epochValue" => 1404219915.395994
                    },
                    "buildSchemeName" => options.name || info.extendedAttributes.buildSchemeName,
                    "scmInfo" => {
                        "/" => {
                            "scmBranch" => options.branch || info.extendedAttributes.scmInfo./.scmBranch
                        }
                    }
                }
            ], 
            ["notifyCommitterOnSuccess", options.successNotify || info.notifyCommitterOnSuccess ], 
            ["notifyCommitterOnFailure", options.failureNotify || info.notifyCommitterOnFailure ]
        ],
        "changeAction" => "UPDATE",
        "entityGUID" => bot_guid,
        "entityRevision" => info.revision,
        "entityType" => "com.apple.entity.Bot",
        "force" => false
    }
    puts JSON.pretty_generate args
    return service_request("ContentService", "updateEntity:", [ args ])
end

def delete_bot (bot_guid)
    args = [ bot_guid ]
    return service_request("XCBotService", "deleteBotWithGUID:", args)
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
    return service_request("XCBotService", "botForGUID:", args)
end

## When you're not sure what entity a GUID represents, use this to find out
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
            :range       => [0, 100],
            :onlyDeleted => false
        }
    ]
    response = service_request("SearchService", "query:", args)

    bots = Array.new
    results = response.results.map { |b| b.entity }
    results.sort_by! { |b| b.longName } # b.lastActivityTime.epochValue 
    results.each { |b| bots.push(get_bot(b.guid)) }
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
    return get_entity(bot_guid).longName.sstrip
end

def execution_time (dt_object_start, dt_object_end)
    if dt_object_start
        start_time = dt_object_start.epochValue.to_f
        timestamp = start_time.to_date
        if dt_object_end
            end_time = dt_object_end.epochValue.to_f
            timestamp = sprintf "%s - %s (%i mins)", timestamp, end_time.to_date("%l:%M"), ((end_time - start_time) / 60).to_i
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
    puts "-" * 20
    printf "Bot runs for %s\n", get_bot_name(bot_guid)
    results = response.results.sort_by { |b| b.entity.integration }
    results.each_with_index do |result, i|
        puts result.to_h if DEBUG
        entity = result.entity
        column = Array.new
        column.push(sprintf "%-2s", i+1)
        column.push(sprintf " %-5s", "##{entity.integration}")
        column.push(sprintf "%-35s", "#{entity.status} (#{entity.subStatus})")
        column.push(sprintf "%-40s", execution_time(entity.startTime, entity.endTime))
        if VERBOSE
            column.push(entity.guid)
        end
        integrations.push(entity.integration)
        puts column.join
    end
    puts "-" * 20
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

    puts "-" * 20, title
    # puts response.to_h
    attr = response.extendedAttributes
    if attr.output
        build_output = attr.output.build 

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
    end

    #puts errors, actions, archive_path, is_running, analyzer_warnings

    title = sprintf "%s (%s)\n", attr.longName, attr.guid
    printf "%s\n%s\n", title, "=" * title.length
    puts "-" * 20
end

## 
# Class overload
##

# http://andreapavoni.com/blog/2013/4/create-recursive-openstruct-from-a-ruby-hash/#.U6z4xY1g5vk
# And my additional bug fixes
class DeepStruct < OpenStruct
    def initialize(object=nil)
        @table = {}
        @hash_table = {}
        @object = nil
        if object.is_a?(Hash)
            object.each do |k,v|
                k = k.to_s
                if v.is_a?(Array)
                    v.map! { |e| self.class.new(e) }
                end
                @table[k.to_sym] = (v.is_a?(Hash) ? self.class.new(v) : v)
                @hash_table[k.to_sym] = v
                new_ostruct_member(k)
            end
        else
            @object = object
        end
    end

    def to_h
        return @object if @object
        JSON.pretty_generate @hash_table
    end
end

# Strip out special spaces (Alt+space)
class String
    def sstrip
        self.tr(" ", " ").strip
    end
end

class Float
    def to_date (format = "%a %b %d, %l:%M %p")
        Time.at(self).strftime(format)
    end
end






##
# Sanitized methods
##

def bot_names
  bots = get_bots
end
