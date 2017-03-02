if not (process.env.page_token and process.env.verify_token and process.env.app_secret and process.env.wit_client_token)
  console.log 'Error: Specify page_token, verify_token, app_secret, wit_client_token in environment'
  process.exit 1

Botkit = require 'botkit'
os = require 'os'
commandLineArgs = require 'command-line-args'
localtunnel = require 'localtunnel'
request = require 'request'
lib = require './lib'

ops = commandLineArgs [
  name: 'lt'
  alias: 'l'
  args: 1
  description: 'Use localtunnel.me to make your bot available on the web.'
  type: Boolean
  defaultValue: false
,
  name: 'ltsubdomain'
  alias: 's'
  args: 1,
  description: 'Custom subdomain for the localtunnel.me URL. This option can only be used together with --lt.'
  type: String
  defaultValue: null
]

if ops.lt is false and ops.ltsubdomain isnt null
  console.log "error: --ltsubdomain can only be used together with --lt."
  process.exit()

controller = Botkit.facebookbot
  debug: true
  log: true
  access_token: process.env.page_token
  verify_token: process.env.verify_token
  app_secret: process.env.app_secret
  validate_requests: true           # // Refuse any requests that don't come from FB on your receive webhook, must provide FB_APP_SECRET in environment variables

bot = controller.spawn()

controller.setupWebserver process.env.port or 3000, (err, webserver) ->
  controller.createWebhookEndpoints webserver, bot, () ->
    console.log 'ONLINE!'
    if ops.lt
      tunnel = localtunnel process.env.port or 3000, subdomain: ops.ltsubdomain, (err, tunnel) ->
        if err
          console.log err
          process.exit()
        console.log "Your bot is available on the web at the following URL: #{tunnel.url}/facebook/receive"

      tunnel.on 'close', () ->
        console.log "Your bot is no longer available on the web at the localtunnnel.me URL."
        process.exit()

controller.api.thread_settings.greeting "Hi :), I'm wagbot, an experimental Community Law project. I'm pretty dumb, but I know the answers to some questions you might have about problems at school."

controller.hears ['(.*)'], 'message_received', (bot, message) ->
  lib.log_request message

  question = message.match.input

  if question.match /uptime|identify yourself|who are you|what is your name|what's your name/i
    bot.reply message, ":) I'm wagbot. I've been running for #{lib.formatUptime process.uptime()} on #{os.hostname()}"
  else
    request
      headers:
        'Authorization': "Bearer #{process.env.wit_client_token}"
        'Content-Type': 'application/json'
      uri: "https://api.wit.ai/converse?v=20160526&session_id=#{Math.random().toString(36).substring(2,11)}&q=hi#{question}",
      method: 'POST'
      , (err, res, body) ->
        if err
          bot.reply message, "Sorry, something went wrong :'( — error # #{err}"
        else
          data = JSON.parse(body)
          if data.type is 'stop'
            bot.reply message,
              "attachment":
                "type": "template"
                "payload":
                  "template_type": "button"
                  "text": "Sorry, I've got no idea. Want to talk to someone with some clues?"
                  "buttons": [
                    "type":"phone_number",
                    "title":"📞 Call Community Law",
                    "payload":"+64 4 499 2928"
                  ]
            lib.log_no_kb_match message

          else
            bot.reply message, lib.clean data.msg
            lib.log_response message, data

controller.hears ['shutdown'], 'message_received', (bot, message) ->
  bot.startConversation message, (err, convo) ->
    convo.ask 'Are you sure you want me to shutdown?', [
      pattern: bot.utterances.yes
      callback: (response, convo) ->
        convo.say 'Bye!'
        convo.next()
        setTimeout () ->
          process.exit()
        , 3000
    ,
      pattern: bot.utterances.no
      default: true
      callback: (response, convo) ->
        convo.say '*Phew!*'
        convo.next()
    ]
