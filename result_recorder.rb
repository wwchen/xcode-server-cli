#!/usr/bin/env ruby
require_relative 'xbot'
require "sqlite3"
require "CFPropertyList"

DB_NAME = "test.db"
TABLE_NAME = "botruns"

# TODO for now, map CI bots to Stable bots
bot_mapping = {
    "c6330400-0ac8-0ac8-16bc-aa99269be2b3" => "c6330635-5525-5525-e3a7-e5e663634222",
    "c63305cf-ff1a-ff1a-b929-83607a0fb63c" => "c6330641-124d-124d-397c-a8dc5d2dd762",
    "c633724f-f9fe-f9fe-297c-34da0df158c1" => "c633725c-c6af-c6af-3647-93a905e3e0f9",
    "c63360fc-cfba-cfba-f0dc-469154eb7843" => "c6336103-3289-3289-c79d-79eac9317b27",
    "c6337223-3861-3861-c15b-17724e0acba3" => "c6337263-31b7-31b7-7aaf-64054074c84e",
    "c633722a-a3c9-a3c9-cc2b-87b9b084f7b0" => "c6337269-963f-963f-acbe-a355b4d5a5d6",
    "c6337230-0751-0751-60d0-6feb964c3e16" => "c6337281-1fb4-1fb4-9e49-23cddd79618b",
    "c6337237-712a-712a-a1bc-f953a1737e5d" => "c6337278-8202-8202-37bc-0a5333594218",

    "c633725c-c6af-c6af-3647-93a905e3e0f9" => "c633725c-c6af-c6af-3647-93a905e3e0f9",
}

# this script will record the status of the finished bot run
# to a sqlite database, which will later be queried by stable runner to determine
# which branch or commit to pull

if ARGV.length < 1
    puts "Usage: ./result_recorder.rb <bot_guid>"
    exit 1
end
bot_guid = ARGV[0]

# Open a database
db = SQLite3::Database.new DB_NAME
db.results_as_hash = true

# Create a database
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    botName         TEXT,
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


# Query the server
bot_response    = get_bot bot_guid
botrun_response = get_botrun bot_guid

bot_name      = bot_response.response.longName.sstrip
botrun        = botrun_response.response
botrun_guid   = botrun.guid
botrun_status = botrun.status # NOTE check
botrun_substatus = botrun.subStatus
time          = botrun.lastActivityTime.epochValue
commits       = botrun.scmCommitGUIDs
commit_guid   = commits.first.to_h unless commits.nil? or commits.empty?
commit_id     = nil
commit_msg    = nil

printf "%s's latest run %s with %s. There are %s commits in this integration.\n", bot_name, botrun_status, botrun_substatus, commits.length
puts "Looking into commit with guid #{commit_guid}"
if commit_guid
    commit_response = get_entity commit_guid
    commit     = commit_response.response
    commit_id  = commit.commitID
    commit_msg = commit.message
end

puts "Inserting the collected information into the database"
db.execute("INSERT INTO #{TABLE_NAME}               (botName,  botGUID,  botrunGUID,  botrunStatus,  botrunSubstatus,  commitGUID,  commitID,  commitMessage, stableRan, time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [bot_name, bot_guid, botrun_guid, botrun_status, botrun_substatus, commit_guid, commit_id, commit_msg,    0,         time])


## Query the database
puts "Querying the database for all rows with bot guid #{bot_guid}"
rows = db.execute( "SELECT * FROM #{TABLE_NAME} WHERE
                       botGUID = '#{bot_guid}' AND 
                       commitGUID NOT NULL AND
                       botrunSubstatus = 'succeeded'
                    ORDER BY time ASC " )
row = DeepStruct.new rows.first
if row.stableRan == 0
    stable_guid = bot_mapping[row.botGUID]
    puts "Last succeeded run has not kicked off a Stable build yet. Scheduling one now on #{stable_guid}"
    response = schedule_botrun stable_guid
    db.execute "UPDATE #{TABLE_NAME} SET stableRan=1 WHERE id=#{row.id}" if response.succeeded
else
    puts "Last succeeded run has already kicked off a Stable build. Our job is complete"
end
exit

# We now know when the build was completed, and what commit was last made in this build.
# Let's check if we've already built this, and let's 
if not row.stableRan
    schedule_botrun bot_mapping[row.botGUID]
    # run the stable bot, and mark the row as ran
end

# Using this information, checkout git and do something about it

# NOTE Example of now you would read a plist file. Pretty straightforward, and keeps it clean by converting to native datatypes
plist_file = CFPropertyList::List.load('some.plist')
plist_hash = CFPropertyList.native_types plist_file.value
plist = DeepStruct.new plist_hash
