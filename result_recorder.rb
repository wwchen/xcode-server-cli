#!/usr/bin/env ruby
require_relative 'xbot'
require "sqlite3"
require "CFPropertyList"
#require "git"

DB_NAME = "test.db"
TABLE_NAME = "botruns"
CI_BRANCH = "main"
STABLE_BRANCH = "stable"

# this script will record the status of the finished bot run
# to a sqlite database, which will later be queried by stable runner to determine
# which branch or commit to pull

if ARGV.length < 1
    puts "Usage: ./result_recorder.rb <bot_guid> <path_to_config_file>"
    exit 1
end
bot_guid = ARGV[0]
ciconfig_filepath = ARGV[1]

config_file = CFPropertyList::List.new(:file => ciconfig_filepath)
config = CFPropertyList.native_types config_file.value

# find out what app and branch this bot belongs to, by looking through the whole config plist
app = ""
branch = ""
config["App"].each do |app_name, app_config|
    app_config["Branches"].each do |branch_name, branch_config|
        branch_config.values.each do |bot|
            if bot_guid == bot["GUID"]
                app = app_name
                branch = branch_name
            end
        end
    end
end

if app.empty? or branch.empty?
    puts "Could not find a matching bot guid: #{bot_guid}! Exiting.."
    exit
end

# if we are in CI branch, we want to record our build status and TODO merge to stable
# if we are in stable branch, we want to ???

# Open the database
db = SQLite3::Database.new DB_NAME
db.results_as_hash = true

# Create a database if not exists
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    appName         TEXT,
    appBranch       TEXT,
    botGUID         TEXT,
    botStatus       TEXT,
    botrunGUID      TEXT,
    botrunStatus    TEXT,
    botrunSubstatus TEXT,
    commitGUID      TEXT,
    commitID        TEXT,
    commitMessage   TEXT,
    stableRan       BOOLEAN,
    time            FLOAT
  );
SQL

if branch == CI_BRANCH
    # Query the server
    bot_response    = get_bot bot_guid
    botrun_response = get_botrun bot_guid

    bot_name      = bot_response.longName.sstrip
    botrun        = botrun_response
    botrun_guid   = botrun.guid
    botrun_status = botrun.status
    botrun_substatus = botrun.subStatus
    time          = botrun.lastActivityTime.epochValue
    commits       = botrun.scmCommitGUIDs or []
    commit_guid   = commits.first.to_h unless commits.empty?
    commit_id     = nil
    commit_msg    = nil

    printf "%s's latest run %s with %s. There are %s commits in this integration.\n", bot_name, botrun_status, botrun_substatus, commits.length
    if commit_guid
        puts "Looking into commit with guid #{commit_guid}"
        commit     = get_entity commit_guid
        commit_id  = commit.commitID
        commit_msg = commit.message

        puts "Inserting the collected information into the database"
        db.execute("INSERT INTO #{TABLE_NAME}                  (appName, appBranch, botGUID,  botrunGUID,  botrunStatus,  botrunSubstatus,  commitGUID,  commitID,  commitMessage, stableRan, time)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [app,     branch,    bot_guid, botrun_guid, botrun_status, botrun_substatus, commit_guid, commit_id, commit_msg,    0,         time])


        # push to git, if there are new commits since last run, and we are green
        # if commit_guid and botrun_status == "Succeeded"
        #     # git clone or reuse the git repo?
        #     git = Git.clone url, name, :path => "/tmp/checkout" # TODO
        #     git.config("user.name", "AXP iOS Admin")
        #     git.config("user.email", "axpiosadmin@microsoft.com")
        #     git.checkout "main"
        #     git pull
        #     git.checkout "stable"
        #     git.remote("main").merge("stable")
        #     git push
        # end
    end
end

if branch == STABLE_BRANCH
    ## Query the database, see if the latest success build was already executed
    puts "Querying the database for all rows with bot guid #{bot_guid}"
    row = db.get_first_row( "SELECT * FROM #{TABLE_NAME} WHERE
                                appName = '#{app}' AND 
                                appBranch = '#{CI_BRANCH}' AND
                                commitGUID NOT NULL AND
                                botrunSubstatus = 'succeeded'
                             ORDER BY time ASC " )
    row = DeepStruct.new row
    if row.stableRan == 0
        puts "Last succeeded run has not kicked off a Stable build yet."
        puts "First change the bot branch to point to commit #{row.commitID} (#{row.commitMessage})"
        response = change_bot_settings bot_guid, { "branch" => row.commitID }
        puts response
        puts "Scheduling one now on #{bot_guid}"
        response = schedule_botrun bot_guid
        db.execute "UPDATE #{TABLE_NAME} SET stableRan=1 WHERE id=#{row.id}"
    else
        puts "Last succeeded run has already kicked off a Stable build. Our job is complete"
    end
    exit

    # We now know when the build was completed, and what commit was last made in this build.
    # Let's check if we've already built this, and let's 
    #if not row.stableRan
    #    schedule_botrun bot_mapping[row.botGUID]
    #    # run the stable bot, and mark the row as ran
    #end

    # Using this information, checkout git and do something about it
end


