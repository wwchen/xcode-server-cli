#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'ostruct'
require 'yaml'

CONFIG = YAML.load_file(File.join(File.dirname(File.expand_path(__FILE__)),"config.yml")) unless defined? CONFIG

SESSION_GUID = CONFIG["SESSION_GUID"]
HOSTNAME = CONFIG["HOSTNAME"]
DEBUG = false
VERBOSE = true
#CHECKMARK = "✔"
#CROSSMARK = "✘"
CACHE_EXPIRY = 5


class ServiceRequestResponse
  @last_update = nil

  def initialize
  end
end

##
# Base classes
##
class Bot < ServiceRequestResponse
  @entity = nil
  @guid = nil
  @botruns = nil

  def initialize(arg)
    if (arg.is_a?(String) && arg.strip.match(/^[0-9a-z-]*$/))
      @guid = arg.strip
      get
    elsif (arg.is_a? Hash)
      # TODO try the actual method here
      response = create(arg)
      @guid = response.guid
      get
    else
      raise ArgumentError, sprintf("Cannot create or find a Bot with argument: %s", arg)
    end
  end

  ## catch-all accessor methods
  # converts snake string to camel case
  # http://apidock.com/rails/ActiveSupport/Inflector/camelize
  def method_missing(method)
    property = method.id2name
    property = property.sub(/^(?=\b|[A-Z_])|\w/) { $&.downcase }
    property = property.gsub(/(?:_|(\/))([a-z\d]*)/) { "#{$1}#{$2.capitalize}" }
    get[property] || get.extendedAttributes[property] || raise(NoMethodError, property + " does not exist")
  end

  ## shorthand accessors
  def name
    return get.longName.sstrip
  end

  def scm_guid
    return get.extendedAttributes.scmInfoGUIDMap./
  end

  ## action verbs: create, update, delete, get, integrate, cancel
  def cancel
    ServiceRequest.xcbot_service("cancelBotRunWithGUID:", [@guid])
  end

  def integrate
    ServiceRequest.xcbot_service("startBotRunForBotGUID:", [@guid])
  end

  def delete
    ServiceRequest.xcbot_service("deleteBotWithGUID:", [@guid])
  end

  def get
    now = Time.now.to_i
    if !@last_update || (now - @last_update) > CACHE_EXPIRY
      @entity = ServiceRequest.xcbot_service("botForGUID:", [@guid])
    end
    @last_update = now
    return @entity
  end
  private :get

  def create(options)
    # required fields
    options = DeepStruct.new options
    raise ArgumentError unless options.name and
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
                "/" => options.scmGUID  # 2ded7b82-44b1-b7d0-4ca8-15a6a266c7f1
            },
            "buildProjectPath"  => options.buildProjectPath,
            "buildSchemeName"   => options.buildSchemeName,
            "pollForSCMChanges" => options.pollForSCMChanges || false,
            "buildOnTrigger"    => options.buildOnTrigger || false,
            "buildFromClean"    => options.buildFromClean || 0, # 1: always, 2: once a day
            "integratePerformsAnalyze" => options.integratePerformsAnalyze || true,
            "integratePerformsTest"    => options.integratePerformsTest || true,
            "integratePerformsArchive" => options.integratePerformsArchive || true,
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
    return ServiceRequest.xcbot_service("createBotWithProperties:", [ args ])
  end
  private :create

  def update (options)
      # TODO also need to send updateEmailSubscriptionList:forEntityGUID:withNotificationType:
      # and deleteWorkScheduleWithEntityGUID:
      options = DeepStruct.new options

      get
      args = {
          "type" => "com.apple.EntityChangeSet",
          "changes" => [
              [
                  "longName", options.name || @entity.longName
              ], 
              [
                  "extendedAttributes",
                  {
                      "buildFromClean" => options.buildFromClean || @entity.extendedAttributes.buildFromClean,
                      "buildOnTrigger" => options.buildOnTrigger || @entity.extendedAttributes.buildOnTrigger,
                      "deviceInfo"     => options.deviceInfo || @entity.extendedAttributes.deviceInfo.map { |a| a.to_h },
                      "deviceSpecification" => options.deviceType || @entity.extendedAttributes.deviceSpecification,
                      "buildProjectPath" => options.buildPath || @entity.extendedAttributes.buildProjectPath,
                      "pollForSCMChanges" => options.pollForChanges || @entity.extendedAttributes.pollForSCMChanges,
                      "scmInfoGUIDMap" => {
                          "/" => @entity.extendedAttributes.scmInfoGUIDMap./
                      },
                      "integratePerformsTest" => options.integratePerformsTest || @entity.extendedAttributes.integratePerformsTest,
                      "integratePerformsAnalyze" => options.integratePerformsAnalyze || @entity.extendedAttributes.integratePerformsAnalyze,
                      "integratePerformsArchive" => options.integratePerformsArchive || @entity.extendedAttributes.integratePerformsArchive,
                      "lastBuildFromCleanTime" => @entity.extendedAttributes.lastBuildFromCleanTime.to_h,
                      "lastBuildFromCleanTime" =>  {
                          "type" => "com.apple.DateTime",
                          "isoValue" => "2014-07-01T06:05:15.396-0700",
                          "epochValue" => 1404219915.395994
                      },
                      "buildSchemeName" => options.name || @entity.extendedAttributes.buildSchemeName,
                      "scmInfo" => {
                          "/" => {
                              "scmBranch" => options.branch || @entity.extendedAttributes.scmInfo./.scmBranch
                          }
                      }
                  }
              ], 
              ["notifyCommitterOnSuccess", options.successNotify || @entity.notifyCommitterOnSuccess ], 
              ["notifyCommitterOnFailure", options.failureNotify || @entity.notifyCommitterOnFailure ]
          ],
          "changeAction" => "UPDATE",
          "entityGUID" => @entity.guid,
          "entityRevision" => @entity.revision,
          "entityType" => "com.apple.entity.Bot",
          "force" => false
      }
      if DEBUG
          puts JSON.pretty_generate args
      end
      return ServiceRequest.content_service("updateEntity:", [ args ])
  end

  def botrun (integration_no = nil)
    return BotRun.new(@guid, integration_no)
  end

  # TODO (code review it)
  def botruns (limit = 25)
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
    response = ServiceRequest.search_service("query:", args)

    botruns = Array.new
    results = response.results.map { |b| b.entity }
    results.sort_by! { |b| b.integratoin }
    results.each { |b| botruns.push BotRun.new(b.guid) }
    return botruns
  end

  ## prints
  def latest_run
  end

  def latest_run_status
    return sprintf "%s (%s)", @entity.latestRunStatus, @entity.latestRunSubStatus
  end

  def to_s(type = "summary")
    case type
    when "summary"
    when "raw"
      return @entity.to_h
    else
      raise ArguementError, sprintf("No such type: %s", type)
    end
  end

end

# TODO fix it up, make sense with Bot
class BotRun < ServiceRequestResponse
  @entity = nil
  @owner_guid = nil
  @last_update = nil

  def initialize(bot_guid, integration_no = nil)
    @owner_guid = bot_guid
    get(bot_guid, integration_no)
  end

  def get(bot_guid, integration_no = nil)
    now = Time.now.to_i
    # unless the status is not determined (i.e. succeeded or failed), then query the service
    if(!@last_update || (!(@entity.status =~ /(completed|failed)/) && (now - @last_update) > CACHE_EXPIRY))
      if integration_no
          args = [ @guid, integration_no ]
          @entity = ServiceRequest.xcbot_service("botRunForBotGUID:andIntegrationNumber:", args)
      else
          @entity = ServiceRequest.xcbot_service("latestTerminalBotRunForBotGUID:", [@guid])
      end
    end
    @last_update = now
    return @entity
  end
  private :get

  ## catch-all accessor methods
  # converts snake string to camel case
  # http://apidock.com/rails/ActiveSupport/Inflector/camelize
  def method_missing(method)
    property = method.id2name
    property = property.sub(/^(?=\b|[A-Z_])|\w/) { $&.downcase }
    property = property.gsub(/(?:_|(\/))([a-z\d]*)/) { "#{$1}#{$2.capitalize}" }
    get[property] || get.extendedAttributes[property] || raise(NoMethodError, property + " does not exist")
  end
  # status and sub_status


  def to_s(type = "summary")
    case type
    when "summary"
      bot = Bot.new bot_guid
      response = bot.botrun
      puts response.to_h if DEBUG

      title = ""
      if integration_no
        title = sprintf "Bot run (%i) for %s\n", integration_no, bot.name
      else
        title = sprintf "Latest bot run for %s\n", bot.name
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
    else
      reaise ArgumentError, sprintf("No such type: %s", type)
    end
  end

end

class ServiceRequest
  ## Makes the PUT request to call Xcode apache/collabd/sprocket's REST API
  def self.get_response (hostname, body)
      url = URI "http://#{hostname}/xcs/svc"
      headers = { 'content-type' => 'application/json; charset=UTF-8', 'accept' => 'application/json' }
      http = Net::HTTP.new hostname
      if DEBUG
          puts JSON.pretty_generate(body)
      end
      resp = http.put(url, body.to_json, headers)
      return JSON.parse(resp.body)
  end
  private_class_method :get_response

  ## Prepare and send out a ServiceRequest 
  def self.request (service_name, method_name, arguments)
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
  private_class_method :request

  def self.search_service(method, arg)
    return request("SearchService", method, arg)
  end

  def self.content_service(method, arg)
    return request("ContentService", method, arg)
  end

  def self.xcbot_service(method, arg)
    return request("XCBotService", method, arg)
  end
end


  #####################################################################


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

#####################################################################



##
# Query responses
##

## When you're not sure what entity a GUID represents, use this to find out
def get_entity (guid)
  return ServiceRequest.content_service("entityForGUID:", [ guid ])
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
  response = ServiceRequest.search_service("query:", args)

  bots = Array.new
  results = response.results.map { |b| b.entity }
  results.sort_by! { |b| b.longName } # b.lastActivityTime.epochValue 
  results.each { |b| bots.push Bot.new(b.guid) }
  return bots
end



##
# Helper get methods
##
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
end
