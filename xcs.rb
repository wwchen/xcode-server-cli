#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'openssl'
require 'ostruct'
require 'yaml'
require 'singleton'

DEBUG = false
VERBOSE = false
CHECKMARK = "✔"
CROSSMARK = "✘"
CACHE_EXPIRY = 5

#####################################################################

# Strip out special spaces (Alt+space)
class String
    def to_utf8
        self.encode('UTF-8', { :invalid => :replace, :undef => :replace, :replace => '' })
    end
end

class Float
    def to_date (format = "%a %b %d, %l:%M %p")
        Time.at(self).strftime(format)
    end
end

#####################################################################

# to view all supported routes, see the Xcode Server source code:
# /Applications/Xcode.app/Contents/Developer/usr/share/xcs/xcsd/routes/routes.js
class XCodeAPI
    @hostname = nil
    @username = nil
    @password = nil
    @http = nil
    @auth_cookie = nil

    def initialize (config_file = nil)
        if config_file
            config = YAML.load_file config_file
            set_hostname config["HOSTNAME"]
            set_credentials config["USERNAME"], config["PASSWORD"]
            puts "Config file loaded: #{config_file}" if VERBOSE
        else
            puts "No config file provided" if VERBOSE
        end
    end

    def set_hostname (hostname)
        @hostname = hostname.strip

        @http = Net::HTTP.new(@hostname, 20343)
        @http.use_ssl = true
        @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    def set_credentials (username, password)
        @username = username.strip
        @password = password.strip
    end

    def login
        if @username && @password && @auth_cookie.nil?
            request = Net::HTTP::Post.new "/api/auth/login"
            request.basic_auth @username, @password
            response = @http.request request
            @auth_cookie = response["Set-Cookie"]
            puts @auth_cookie if VERBOSE
        end
    end

    # TODO headers
    def get_request (pathString, headers = {})
        login
        request = Net::HTTP::Get.new "/api/#{pathString}"
        request["Cookie"] = @auth_cookie
        return @http.request request
    end

    # TODO headers
    def post_request (pathString, data, headers = {})
        request = Net::HTTP::Post.new "/api/#{pathString}"
        request["Cookie"] = @auth_cookie
        request.set_form_data data
        return @http.request request
    end
end

# TODO for a lack of a better class name..
class XCodeAPIInterface
    include Singleton
    @api = nil

    def initialize
        config_filename = "config.yml"
        config_file = File.join(File.dirname(File.expand_path(__FILE__)), config_filename)
        @api = XCodeAPI.new config_file
    end

    def make_request (type, url, data = nil)
        response = nil
        if type == "get" || type == "GET"
            response = @api.get_request url
        elsif type == "post" || type == "PUT"
            raise ArgumentError, "data cannot be nil" if data.nil?
            response = @api.post_request url, data
        end

        # TODO raise the correct exceptions
        case response
        when Net::HTTPSuccess, Net::HTTPOK, Net::HTTPCreated
            return JSON.parse response.body.to_utf8
        when Net::HTTPUnauthorized
            puts "Unauthorized"
        when nil
            raise IOError, "#{type} request failed: response is nil for #{url}"
        else
            return response.value
            #raise Net::HTTPError, response.value, response
            #raise Net::HTTPError, "#{type} request failed: #{url}", response
        end
    end

    # health and misc
    def ping
        return make_request "get", "ping"
    end

    def hostname
        return make_request "get", "hostname"
    end

    def health
        return make_request "get", "health"
    end

    # bots
    def list_bots
        return make_request "get", "bots"
    end

    def find_bot (id)
        return make_request "get", "bots/#{id}"
    end

    def create_bot (data)
        return make_request "post", "bots", data
    end

    def show_bot_stats (id)
        return make_request "get", "bots/#{id}/stats"
    end

    # integrations
    def create_integration_for_bot (bot_id, data)
        return make_request "post", "bots/#{bot_id}/integrations", data
    end

    def integration_count_for_bot (bot_id)
        return make_request "get", "bots/#{bot_id}/integrations/count"
    end

    def integrations_for_bot (bot_id)
        return make_request "get", "bots/#{bot_id}/integrations"
    end

    def find_integration (id)
        return make_request "get", "integrations/#{id}"
    end

    def filter_integrations (filter)
        queryString = URI.encode_www_form filter
        return make_request "get", "integrations?#{filter}"
    end

    def filter_integrations_for_bot (bot_id, filter)
        queryString = URI.encode_www_form filter
        return make_request "get", "bots/#{bot_id}/integrations?#{filter}"
    end

    def cancel_integration (id)
        return make_request "post", "integrations/#{id}/cancel"
    end
end

class XCodeInteractive
    def self.print_bots
        interface = XCodeAPIInterface.instance
        response = interface.list_bots

        count = response["count"]
        results = response["results"]
        printf "%-8s %-25s %-15s %-10s %s\n", "Type", "Name", "Scheme", "Tiny ID", "ID"
        puts "=" * 94
        results.each do |result|
            printf("%-8s %-25s %-15s %-10s %s\n",
                result["doc_type"],
                result["name"],
                result["configuration"]["schemeName"],
                result["tinyID"],
                result["_id"])
        end
        puts "Total bots: #{count}"
    end

    def self.print_bot_configuration (id)
        interface = XCodeAPIInterface.instance
        response = interface.find_bot id

        puts JSON.pretty_generate response if DEBUG

        puts response["name"]
        puts "=" * 80
        printf "%-20s: %s\n",                "id", response["_id"]
        printf "%-20s: %s\n",           "tiny id", response["tinyID"]
        printf "%-20s: %s\n",      "integrations", response["integration_counter"]
        printf "%-20s: %s\n",            "scheme", response["configuration"]["schemeName"]
        printf "%-20s: %s\n",       "clean build", response["configuration"]["buildFromClean"]
        printf "%-20s: %s\n", "schedule interval", response["configuration"]["periodicScheduleInterval"]
        printf "%-20s: %s\n",   "testing devices", response["configuration"]["testingDeviceIDs"].to_s
        printf "%-20s: %s\n",     "schedule type", response["configuration"]["scheduleType"].to_s
        printf "%-20s: %s\n",             "test?", response["configuration"]["performsTestAction"].to_s
        printf "%-20s: %s\n",          "analyze?", response["configuration"]["performsAnalyzeAction"].to_s
        printf "%-20s: %s\n",          "archive?", response["configuration"]["performsArchiveAction"].to_s
        puts "-" * 80
        puts "Source control info"
        puts "-" * 80
        repo_id = response["configuration"]["sourceControlBlueprint"]["DVTSourceControlWorkspaceBlueprintPrimaryRemoteRepositoryKey"]
        printf "%-20s: %s\n",              "name", response["configuration"]["sourceControlBlueprint"]["DVTSourceControlWorkspaceBlueprintLocationsKey"][repo_id]["DVTSourceControlBranchIdentifierKey"]
        printf "%-20s: %s\n",                "id", repo_id
        printf "%-20s: %s\n",      "project path", response["configuration"]["sourceControlBlueprint"]["DVTSourceControlWorkspaceBlueprintRelativePathToProjectKey"]
        printf "%-20s: %s\n", "working copy path", response["configuration"]["sourceControlBlueprint"]["DVTSourceControlWorkspaceBlueprintWorkingCopyPathsKey"][repo_id]
        puts "-" * 80
        puts "Triggers"
        puts "-" * 80
        triggers = response["configuration"]["triggers"]
        triggers.each_with_index do |trigger, index|
            printf "%-20s: %s\n",        "name", trigger["name"]
            printf "%-20s: %s\n",        "type", trigger["type"]
            printf "%-20s: %s\n",       "phase", trigger["phase"]
            printf "%-20s: %s\n",  "conditions", trigger["conditions"].to_s
            printf "%-20s: %s\n", "script body", trigger["scriptBody"].delete("\n") if trigger["scriptBody"] 
            puts "-" * 40 if index % 2 == 1
        end
    end

    def self.print_integrations_for_bot (id, count = nil)
        interface = XCodeAPIInterface.instance
        response = interface.integrations_for_bot id
        puts JSON.pretty_generate reponse if DEBUG
        count = response["count"]
        results = response["results"]
        if count > 1
            name = results.first["bot"]["name"]
            puts "Integrations for bot: #{name}"
            puts "=" * 80
            printf "%-8s %-25s %-15s %-10s %-10s %-10s %-10s %-16s %-8s %-8s %-12s %s\n", "Number", "Status", "Result", "Analyzer", "Warning", "Error", "Test", "Queued", "Start", "End", "Duration", "ID"
            results.reverse.each do |result|
                status = result["currentStep"]
                printf("%-8s %-25s %-15s %-10s %-10s %-10s %-10s %-16s %-8s %-8s %-12s %s\n",
                    result["number"],
                    status,
                    result["result"],
                    result["buildResultSummary"]["analyzerWarningCount"],
                    result["buildResultSummary"]["warningCount"],
                    result["buildResultSummary"]["errorCount"],
                    result["buildResultSummary"]["testsCount"],
                    DateTime.parse(result["queuedDate"]).to_time.getlocal.strftime("%b %d, %R"),
                    status =~ /pending/ ? "-" : DateTime.parse(result["startedTime"]).to_time.getlocal.strftime("%R"),
                    status =~ /pending/ ? "-" : DateTime.parse(result["endedTime"]).to_time.getlocal.strftime("%R"),
                    result["duration"],
                    result["_id"])
            end
        end
    end

    def self.print_integration (id)
        interface = XCodeAPIInterface.instance
        response = interface.find_integration id
        puts JSON.pretty_generate response if DEBUG

        bundle_name = response["assets"]["product"]["infoDictionary"]["CFBundleExecutable"]
        puts "Integration for product: #{bundle_name}"
        puts "=" * 80
        printf "%-20s: %s\n",                 "id", response["_id"]
        printf "%-20s: %s\n",            "tiny id", response["tinyID"]
        printf "%-20s: %s\n",             "bot id", response["bot"]["_id"]
        printf "%-20s: %s\n",      "current state", response["currentStep"]
        printf "%-20s: %s\n",             "number", response["number"]
        printf "%-20s: %s\n",        "queued date", response["queuedDate"]
        printf "%-20s: %s\n",     "success streak", response["success_streak"]
        printf "%-20s: %s\n",               "tags", response["tags"].to_s
        printf "%-20s: %s\n",         "start time", response["startedTime"]
        printf "%-20s: %s\n",           "end time", response["endedTime"]
        printf "%-20s: %s\n",           "duration", response["duration"]
        printf "%-20s: %s\n",      "build summary", response["buildResultSummary"].to_s
        printf "%-20s: %s\n",             "result", response["result"]
        printf "%-20s: %s\n",            "product", response["assets"]["product"]["relativePath"]
        printf "%-20s: %s\n", "source control log", response["assets"]["sourceControlLog"]["relativePath"]
        printf "%-20s: %s\n",            "archive", response["assets"]["archive"]["relativePath"]
        printf "%-20s: %s\n",   "xcodebuildOutput", response["assets"]["xcodebuildOutput"]["relativePath"]
        printf "%-20s: %s\n",          "build log", response["assets"]["xcodebuildLog"]["relativePath"]
        printf "%-20s: %s\n",  "build service log", response["assets"]["buildServiceLog"]["relativePath"]
        response["assets"]["triggerAssets"].each do |triggerAsset|
            printf "%-20s: %s\n",    "trigger log", triggerAsset["relativePath"]
        end
    end

    def self.integrate_bot (id)
        interface = XCodeAPIInterface.instance
        # get the latest bot configuration
        response = interface.find_bot id
        # make a new integration with that config
        response = interface.create_integration_for_bot id, response
        printf "%s iteration %s scheduled.\n", response["_id"], response["number"]
    end

    def self.find_bot_ids_by_scm_info (branch, project = nil, scheme = nil)
        interface = XCodeAPIInterface.instance
        response = interface.list_bots
        bot_ids = Array.new

        results = response["results"]
        results.each do |result|
            bot_id = result["_id"]
            response = interface.find_bot bot_id
            repo_id = response["configuration"]["sourceControlBlueprint"]["DVTSourceControlWorkspaceBlueprintPrimaryRemoteRepositoryKey"]
            branch_name  = response["configuration"]["sourceControlBlueprint"]["DVTSourceControlWorkspaceBlueprintLocationsKey"][repo_id]["DVTSourceControlBranchIdentifierKey"]
            project_path = response["configuration"]["sourceControlBlueprint"]["DVTSourceControlWorkspaceBlueprintRelativePathToProjectKey"]
            scheme_name = response["configuration"]["schemeName"]

            criteria = branch_name == branch
            criteria &= scheme_name == scheme if scheme
            criteria &= project_path =~ Regexp.new(project, Regexp::IGNORECASE) if project
            if criteria
                bot_ids.push bot_id
            end
        end
        return bot_ids
    end

    def self.find_bot_ids_by_name (name_regex)
        interface = XCodeAPIInterface.instance
        response = interface.list_bots
        bot_ids = Array.new

        results = response["results"]
        results.each do |result|
            bot_id = result["_id"]
            bot_name = result["name"]
            if bot_name =~ Regexp.new(name_regex, Regexp::IGNORECASE)
                bot_ids.push bot_id
            end
        end
        return bot_ids
    end

    def self.cancel_pending_integrations
        interface = XCodeAPIInterface.instance
        filter = { "currentStep" => "pending" }
        response = interface.filter_integrations filter
        response["results"].each do |result|
            interface.cancel_integration result["_id"]
        end
    end

    def self.cancel_pending_integrations_for_bot_id (bot_id)
        interface = XCodeAPIInterface.instance
        filter = { "currentStep" => "pending" }
        response = interface.filter_integrations_for_bot bot_id, filter
        response["results"].each do |result|
            interface.cancel_integration result["_id"]
        end
    end

    # TODO not proud of this function
    def self.stop_integrations_for_bot_id (bot_id)
        interface = XCodeAPIInterface.instance
        filter = { "currentStep" => "building" }
        response = interface.filter_integrations_for_bot bot_id, filter
        response["results"].each do |result|
            interface.cancel_integration result["_id"]
        end
        filter = { "currentStep" => "archiving" }
        response = interface.filter_integrations_for_bot bot_id, filter
        response["results"].each do |result|
            interface.cancel_integration result["_id"]
        end
    end
end


##
# main entry point

# usage example
# XCodeInteractive.print_bots
# XCodeInteractive.print_bot_configuration "92a60c96b41506e3528c9945a245ad7c"
# XCodeInteractive.print_integrations_for_bot "92a60c96b41506e3528c9945a245ad7c"
# XCodeInteractive.print_integration "92a60c96b41506e3528c9945a245d78d"
# puts XCodeInteractive.find_bot_ids_by_scm_info "main", "common/AXPlatformTest/AXPlatformTest.xcodeproj"


#####################################################################
