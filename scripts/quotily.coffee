# Description
#   Quotily, Bot for quotes
#
# Dependencies:
#   "<module name>": "<module version>"
#
# Configuration:
#   LIST_OF_ENV_VARS_TO_SET
#
# Commands:
#       quotilybot help - Displays help message
#		quotilybot sleep it off - 'Zzz' 
#		quotilybot schedule [cancel|del|delete|remove] <id> - Cancel the schedule
#		quotilybot schedule list - List all scheduled quote messaging
#		quotilybot give me a quote - Reply with a random quote
#		quotilybot bug-me - Reply with a DM of a random quote 
#		quotilybot bug <handle>- Sends a random quote to the <handle>
#		quotilybot display a qoute on this channel every <minute> (minute|minutes) - Sends a random quote every <minute> on the current channel
#	    quotilybot every <minute> (minute|minutes) - shoutcut for above ^^^
#		quotilybot display a qoute on this channel every <hour> (hour|hours) - Sends a random quote every <hour> on the current channel
#       quotilybot every <hour> (hour|hours) - shoutcut for above ^^^
#		quotilybot every working days at <hour>:<minute>(am|pm) - Sends a random quote every Monday through Friday at <hour>:<minute>(am|pm)
#		quotilybot every non-working days at <hour>:<minute>(am|pm) - Sends a random quote every Saturday and Sunday at <hour>:<minute>(am|pm)
#
# Notes:
#   <optional notes required for the script>
#
# Author:
#   @pyjac


quotes = ["`See the light in others and treat them as if that is all you see.` - Wayne Dyer", "`We can do more good by being good, than in any other way.` - Rowland Hill", "`It is our light, not our darkness that most frightens us.` - Marianne Williamson","`Our deepest fear is not that we are inadequate. Our deepest fear is that we are powerful beyond measure.`- Marianne Williamson"]

scheduler = require('node-schedule')
cronParser = require('cron-parser')
{TextMessage} = require('hubot')
JOBS = {}
JOB_MAX_COUNT = 10000
BOT_TZ_DIFF = -1
STORE_KEY = 'quotily_schedule'

pg = require('pg')
connectionString = process.env.DATABASE_URL || 'postgres://localhost:5432/todo'

module.exports = (robot) ->
  robot.brain.on 'loaded', =>
    syncSchedules robot

  if !robot.brain.get(STORE_KEY)
    robot.brain.set(STORE_KEY, {})

  # helper method to get sender of the message
  get_username = (response) ->
    "@#{response.message.user.name}"
   

  # helper method to get channel of originating message
  get_channel = (response) ->
    if response.message.room == response.message.user.name
      "@#{response.message.room}"
    else
      "##{response.message.room}"

  ###
  # basic example of a fully qualified command
  ###
  # responds to "[botname] sleep it off"
  # note that if you direct message this command to the bot, you don't need to prefix it with the name of the bot
  robot.respond /sleep it off/i, (msg) ->
    # responds in the current channel
    msg.send 'zzz...'

  robot.respond /help/i, (msg) ->
    # responds in the current channel
    msg.send """
    Commands:
quotilybot help - Displays help message

		quotilybot sleep it off - 'Zzz' 

		quotilybot schedule [cancel|del|delete|remove] <id> - Cancel the schedule

		quotilybot schedule list - List all scheduled quote messaging

		quotilybot give me a quote - Reply with a random quote

		quotilybot bug me - Reply with a DM of a random quote 

		quotilybot bug <handle> with a quote - Sends a random quote to the <handle>

		quotilybot bug <handle> - Sends a random quote to the <handle>

		quotilybot display a qoute on this channel every <minute> (minute|minutes) - Sends a random quote                           every <minute> on the current channel

		quotilybot every <minute> (minute|minutes) - shoutcut for above ^^^

		quotilybot display a qoute on this channel every <hour> (hour|hours) - Sends a random quote every                             <hour> on the current channel

		quotilybot every <hour> (hour|hours) - shoutcut for above ^^^

		quotilybot every working days at <hour>:<minute>(am|pm) - Sends a random quote every Monday through                                    Friday at <hour>:<minute>(am|pm)
		
		quotilybot every non-working days at <hour>:<minute>(am|pm) - Sends a random quote every Saturday and Sunday                            at <hour>:<minute>(am|pm)
    """

  robot.respond /schedule list/i, (msg) ->
    text = ''
    for id, job of JOBS
      room = job.user.room || job.user.reply_to
      if room in [msg.message.user.room, msg.message.user.reply_to]
        text += "#{id}: [ #{job.pattern} ] \##{room} #{job.message} \n"
    if !!text.length
      #text = text.replace(///#{org_text}///g, replaced_text) for org_text, replaced_text of config.list.   #replace_text
      msg.send text
    else
      msg.send 'No messages have been scheduled'

  robot.respond /schedule (?:del|delete|remove|cancel) (\d+)/i, (msg) ->
    cancelSchedule robot, msg, msg.match[1]

  robot.respond /give me a quote/i, (msg) ->
    call = (random_quote) ->
        msg.send "@" + get_username(msg).slice(1) + ":" + random_quote
    get_random_quote(call)


  # A script to watch a channel's new members
  channel_to_watch = '#bot-test'
  robot.enter (msg) ->
    # limit our annoyance to this channel
    if(get_channel(msg) == channel_to_watch)
      # https://github.com/github/hubot/blob/master/docs/scripting.md#random
      msg.send msg.random ['welcome', 'hello', 'who are you?']


  ###
  # Example of building an external endpoint (that lives on your heroku app) for others things to trigger your bot to do stuff
  # To see this in action, visit https://[YOUR BOT NAME].herokuapp.com/hubot/my-custom-url/:room after deploying
  # This could be used to let bots talk to each other, for example.
  # More on this here: https://github.com/github/hubot/blob/master/docs/scripting.md#http-listener
  ###
  # robot.router.get should probably be a .post to prevent spiders from making it fire
  robot.router.get '/hubot/my-custom-url/:room', (req, res) ->
    robot.emit "bug-me", {
      room: req.params.room
      # note the REMOVE THIS PART in this example -- since we are using a GET and the link is being published in the chat room
      # it can cause an infinite loop since slack itself pre-fetches URLs it sees
      source: "a HTTP call to #{process.env.HEROKU_URL or ''}[/ REMOVE THIS PART ]/hubot/my-custom-url/#{req.params.room} (could be any room name)"
    }
    # reply to the browser
    res.send 'OK'

  ###
  # Secondary example of triggering a custom event
  # note that if you direct message this command to the bot, you don't need to prefix it with the name of the bot
  ###
  robot.respond /bug-me/i, (msg) ->
    console.log("In Bugz method")
    robot.emit "bug-me", {
      # removing the @ symbol
      room: get_username(msg).slice(1),
      source: 'use of the bug me command'
    }
  #robot.respond /bug (.*) with a quote$/i, (res) ->
   # usernameToBug = res.match[1]
    #try
      # this will do a private message if the "data.room" variable is the user id of a person
     # call = (random_quote) ->
      #  res.send "@" + get_username(res).slice(1) + ":" + random_quote
      #  res.reply usernameToBug.slice(1) + " has been bugged with a quote"
      #get_random_quote(call)
    #catch error
    

  robot.respond /bug (.*)/i, (res) ->
    usernameToBug = res.match[1]
    try
      # this will do a private message if the "data.room" variable is the user id of a person
      call = (random_quote) ->
        robot.messageRoom usernameToBug.slice(1), get_username(res) + ':' + random_quote
        res.reply usernameToBug.slice(1) + " has been bugged with a quote"
      get_random_quote(call)
      
    catch error
    

  robot.respond /display a quote on this channel every (.*) (minute|minutes)/i, (res) ->
    min = res.match[1]
    pattern = "*/#{min} * * * *"
    schedule robot, res, pattern , get_random_quote
  #Shortcut
  robot.respond /every (.*) (minute|minutes)/i, (res) ->
    min = res.match[1]
    pattern = "*/#{min} * * * *"
    schedule robot, res, pattern , get_random_quote

  robot.respond /display a quote on this channel every (.*) (hour|hours)/i, (res) ->
    hrs = res.match[1]
    pattern = "* */#{hrs} * * *"
    schedule robot, res, pattern , get_random_quote
  #Shortcut
  robot.respond /every (.*) (hour|hours)/i, (res) ->
    hrs = res.match[1]
    pattern = "* */#{hrs} * * *"
    schedule robot, res, pattern , get_random_quote
  
  robot.respond /every working days at (1[012]|[1-9]):([0-5][0-9])(am|pm)/i, (res) ->
  	hrs = new Number(res.match[1])
  	min = new Number(res.match[2])
  	if res.match[3] == "am" && hrs == 12
  	  hrs = 0
    if res.match[3] == "pm"
      hrs += 12
    if (hrs + BOT_TZ_DIFF) == 24
      hrs = 0
    else
      hrs += BOT_TZ_DIFF
  	pattern = "#{min} #{hrs} * * 1-5"
  	schedule robot, res, pattern, get_random_quote

  robot.respond /every non-working days at (1[012]|[1-9]):([0-5][0-9])(am|pm)/i, (res) ->
  	hrs = new Number(res.match[1])
  	min = res.match[2]
  	if res.match[3] == "am" && hrs == 12
  	  hrs = 0
    if res.match[3] == "pm"
      hrs += 12
    if (hrs + BOT_TZ_DIFF) == 24
      hrs = 0
    else
      hrs += BOT_TZ_DIFF
  	pattern = "#{min} #{hrs} * * 0,6"
  	schedule robot, res, pattern, get_random_quote

  ###
  # A generic custom event listener
  # Also demonstrating how to send private messages and messages to specific channels
  # https://github.com/github/hubot/blob/master/docs/scripting.md#events
  ###
  robot.on "bug-me", (data) ->
    try
      # this will do a private message if the "data.room" variable is the user id of a person
      call = (msg) ->
        robot.messageRoom data.room, msg
      get_random_quote(call)
    catch error


  ###
  # Demonstration of how to parse private messages
  ###
  # responds to all private messages with a mean remark
  #robot.hear /./i, (msg) ->
    # you can chain if clauses on the end of a statement in coffeescript to make things look cleaner
    # in a direct message, the channel name and author are the same
  # msg.send 'shoo!' if get_channel(msg) == get_username(msg)

  # any message above not yet processed falls here. See the console to examine the object
  # uncomment to test this
  # robot.catchAll (response) ->
  #   console.log('catch all: ', response)

  ###
  # demo of replying to specific messages
  # replies to any message containing an "!" with an exact replica of that message
  ###
  # .* = matches anything; we access the entire matching string using match[0]
  # for using regex, use this tool: http://regexpal.com/
  #robot.hear /.*!.*/, (msg) ->
    # send back the same message
    # reply prefixes the user's name in front of the text
    #msg.send msg.match[0]


  ###
  # demo of brain functionality (persisting data)
  # https://github.com/github/hubot/blob/master/docs/scripting.md#persistence
  # counts every time somebody says "up"
  # prints out the count when somebody says "are we up?"
  ###
  # /STUFF/ means match things between the slashes. the stuff between the slashes = regular expression.
  # \b is a word boundary, and basically putting it on each side of a phrase ensures we are matching against
  # the word "up" instead of a partial text match such as in "sup"
  #robot.hear /\bup\b/, (msg) ->
    # note that this variable is *GLOBAL TO ALL SCRIPTS* so choose a unique name
    #robot.brain.set('everything_uppity_count', (robot.brain.get('everything_uppity_count') || 0) + 1)



# helper method to get sender of the message
get_random_quote = (callback) ->
  #Get a Postgres client from the connection pool
  quote = "`See the light in others and treat them as if that is all you see.` - Wayne Dyer"
  pg.connect(connectionString, (err, client, done) ->
      # Handle connection errors
      if err
          done()
          quote = err
           
      query = client.query("select * from quotes order by random() limit 1;")
      query.on('row', (row) ->
          quote = "`" + row.quote + "` - " + row.author
          #console.log(" get_random_quote HERE " + quote + row)
          callback(quote)
      )

      # After all data is returned, close connection and return results
      query.on('end', () ->
          done()
          #return res.json(results)
      )
  )


#Scheduling Refenrence: https://github.com/matsukaz/hubot-schedule
schedule = (robot, msg, pattern, message) ->
  if JOB_MAX_COUNT <= Object.keys(JOBS).length
    return msg.send "Too many scheduled messages"

  id = Math.floor(Math.random() * JOB_MAX_COUNT) while !id? || JOBS[id]
  try
    job = createSchedule robot, id, pattern, msg.message.user, message
    if job
      msg.send "#{id}: Schedule created"
    else
      msg.send """Invalid Schedule Values (Note: We use 24 hours Format)"""
  catch error
    return msg.send error.message


createSchedule = (robot, id, pattern, user, message) ->
  if isCronPattern(pattern)
    return createCronSchedule robot, id, pattern, user, message
  #return createCronSchedule robot, id, pattern, user, message
  #date = Date.parse(pattern)
  #if !isNaN(date)
    #if date < Date.now()
      #throw new Error "\"#{pattern}\" has already passed"
  #return createDatetimeSchedule robot, id, pattern, user, message

createCronSchedule = (robot, id, pattern, user, message) ->
  startSchedule robot, id, pattern, user, message


createDatetimeSchedule = (robot, id, pattern, user, message) ->
  startSchedule robot, id, new Date(pattern), user, message, () ->
    delete JOBS[id]
    delete robot.brain.get(STORE_KEY)[id]


startSchedule = (robot, id, pattern, user, message, cb) ->
  job = new Job(id, pattern, user, message, cb)
  job.start(robot)
  JOBS[id] = job
  robot.brain.get(STORE_KEY)[id] = job.serialize()


updateSchedule = (robot, msg, id, message) ->
  job = JOBS[id]
  return msg.send "Schedule #{id} not found" if !job

  job.message = message
  robot.brain.get(STORE_KEY)[id] = job.serialize()
  msg.send "#{id}: Scheduled message updated"


cancelSchedule = (robot, msg, id) ->
  job = JOBS[id]
  return msg.send "#{id}: Schedule not found" if !job

  job.cancel()
  delete JOBS[id]
  delete robot.brain.get(STORE_KEY)[id]
  msg.send "#{id}: Schedule canceled"


syncSchedules = (robot) ->
  if !robot.brain.get(STORE_KEY)
    robot.brain.set(STORE_KEY, {})

  nonCachedSchedules = difference(robot.brain.get(STORE_KEY), JOBS)
  for own id, job of nonCachedSchedules
    scheduleFromBrain robot, id, job...

  nonStoredSchedules = difference(JOBS, robot.brain.get(STORE_KEY))
  for own id, job of nonStoredSchedules
    storeScheduleInBrain robot, id, job


scheduleFromBrain = (robot, id, pattern, user, message) ->
  envelope = user: user, room: user.room
  try
    createSchedule robot, id, pattern, user, message
  catch error
    #robot.send envelope, "#{id}: Failed to schedule from brain. [#{error.message}]" 
    return delete robot.brain.get(STORE_KEY)[id]

  #robot.send envelope, "#{id} scheduled from brain" 


storeScheduleInBrain = (robot, id, job) ->
  robot.brain.get(STORE_KEY)[id] = job.serialize()

  envelope = user: job.user, room: job.user.room
  #robot.send envelope, "#{id}: Schedule stored in brain asynchronously" 


difference = (obj1 = {}, obj2 = {}) ->
  diff = {}
  for id, job of obj1
    diff[id] = job if id !of obj2
  return diff


isCronPattern = (pattern) ->
  if (typeof pattern == 'string' || pattern instanceof String)
    errors = cronParser.parseString(pattern).errors
    return !Object.keys(errors).length
  return false


class Job
  constructor: (id, pattern, user, message, cb) ->
    @id = id
    @pattern = pattern
    # cloning user because adapter may touch it later
    @user = {}
    @user[k] = v for k,v of user
    @message = message
    @cb = cb
    @job
  # Public: Picks a random item from the given items.
  #
  # items - An Array of items.
  #
  # Returns a random item.
  random: (items) ->
    items[ Math.floor(Math.random() * items.length) ]

  start: (robot) ->
    @job = scheduler.scheduleJob(@pattern, =>
      envelope = user: @user, room: @user.room
      call = (random_quote) ->
        robot.send envelope, random_quote
        robot.adapter.receive new TextMessage(@user, random_quote) 
        @cb?()
      get_random_quote(call)
      
    )

  cancel: ->
    scheduler.cancelJob @job if @job
    @cb?()
    
  serialize: ->
    [@pattern, @user, @message]

