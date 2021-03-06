express = require 'express'
path = require 'path'
fs = require 'fs'
util = require 'util'
url = require 'url'
step = require 'step'
akismet = require 'akismet'
sqlite = require 'sqlite3'
markdown = require 'markdown-js'
jade = require 'jade'
cutil = require './libs/util'


class Application

  constructor: () ->
    @initialized = false

    app = express.createServer()
    @expressApp = app

    # Add :css filter to jade
    jade.filters.css = (str) ->
      return '<style>' + str + '</style>'

    # Settings
    appRoot = path.dirname __dirname
    app.set 'settings', {
      rootDir: appRoot
      publicDir: path.join appRoot, 'public'
      albumDir: path.join appRoot, 'public', 'albums'
      thumbDir: path.join appRoot, 'public', 'thumbs'
      uploadDir: path.join appRoot, 'uploads'
      dbFile: path.join appRoot, 'album.sqlite'
      akismetClient: null
    }
 
    # Configuration for production and development
    app.configure () ->
      app.use express.bodyParser()
      app.use express.cookieParser()
      app.use express.session({ secret: '#22agustos' })
      app.use express.logger()
      app.use express.static(path.join(appRoot, 'public'))

    app.configure 'development', () ->
      app.use express.errorHandler {
        dumpExceptions: true
        showStack: true
      }

    app.configure 'production', () ->
      app.use express.errorHandler()

    # View engine
    app.set 'view engine', 'jade'
    app.set 'views', path.join(appRoot, 'views')

    # View helpers
    app.helpers {
      # converts markdown to html
      parse: (mdtext) ->
        return markdown.parse(cutil.escape(mdtext))
    }

    # Dynamic view helpers
    app.dynamicHelpers {

      # settings
      appname: (req, res) ->
        return app.set('settings').appName
      apptitle: (req, res) ->
        return app.set('settings').appTitle
      gakey: (req, res) ->
        return app.set('settings').gaKey
      settings: (req, res) ->
        return app.set('settings')
      stylesheet: (req, res) ->
        return app.set('settings').style
      appurl: (req, res) ->
        parts = { protocol: 'http:', host: req.headers.host }
        return url.format(parts)

      # background settings
      bgcolor: (req, res) ->
        return app.set('settings').backgroundColor
      bgimageurl: (req, res) ->
        bgimage = app.set('settings').backgroundImage
        if app._locals.album
          return '../img/backgrounds/' + bgimage
        else if app._locals.picture
          return '../../img/backgrounds/' + bgimage
        else
          return '/img/backgrounds/' + bgimage

      # returns array of pagination objects
      pagination: (req, res) ->
        pages = app._locals.pageCount
        if pages <= 1
          return null
        else
          return cutil.getPagination req.url, pages

      # returns an array of error messages
      errorMessages: (req, res) ->
        msg = req.flash 'error'
        if not msg or msg.length is 0 then msg = null
        return msg

      # returns an array of info messages
      infoMessages: (req, res) ->
        msg = req.flash 'info'
        if not msg or msg.length is 0 then msg = null
        return msg

      # gets the logged in user
      user: (req, res) ->
        userid = if req.session.userid then req.session.userid else null
        user = app.set 'user'
        if user and user.id is userid then return user else return null

    }


  # Initializes the application
  #
  # callback: err
  init: (callback) ->

    callback = cutil.ensureCallback callback
    dbexists = true
    db = null
    self = @
    app = self.expressApp
    settings = app.set 'settings'

    step(

      # check database
      () ->
        cutil.fileExists settings.dbFile, @
        return undefined

      # open database
      (err, exists) ->
        if err then throw err
        dbexists = exists
        db = new sqlite.Database settings.dbFile, @
        app.set 'db', db
        return undefined

      # make database if it does not exist
      (err) ->
        if err then throw err

        if dbexists
          return null
        else
          db.exec 'DROP TABLE IF EXISTS "Albums";' +
            'DROP TABLE IF EXISTS "Pictures";' +
            'DROP TABLE IF EXISTS "Comments";' +
            'DROP TABLE IF EXISTS "Settings";' +
            'DROP TABLE IF EXISTS "Users";' +
            'CREATE TABLE "Albums" ("id" INTEGER PRIMARY KEY, "name", "dateCreated", "title", "text");' +
            'CREATE TABLE "Pictures" ("id" INTEGER PRIMARY KEY, "name", "dateTaken", "album", "title", "text");' +
            'CREATE TABLE "Comments" ("id" INTEGER PRIMARY KEY, "from", "text", "dateCommented", "album", "picture", "spam", "ip");' +
            'CREATE TABLE "Users" ("id" INTEGER PRIMARY KEY, "name", "password");' +
            'CREATE TABLE "Settings" ("name" PRIMARY KEY, "value");' +
            'CREATE INDEX "albums_name" ON "Albums" ("name");' +
            'CREATE INDEX "pictures_name" ON "Pictures" ("name");' +
            'CREATE INDEX "pictures_album" ON "Pictures" ("album");' +
            'CREATE INDEX "comments_album" ON "Comments" ("album");' +
            'CREATE INDEX "comments_picture" ON "Comments" ("picture");' +
            'CREATE INDEX "comments_spam" ON "Comments" ("spam");' +
            'INSERT INTO "Users" ("name", "password") VALUES ("admin", "' + cutil.makeHash('admin') + '");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("albumsPerPage", "20");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("picturesPerPage", "40");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("allowComments", "1");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("monitorInterval", "1");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("appName", "canphotoblog");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("appTitle", "canphotoblog");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("appAuthor", "");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("style", "Polaroid.css");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("backgroundColor", "");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("backgroundImage", "");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("akismetKey", "");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("akismetURL", "");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("gaKey", "");' +
            'INSERT INTO "Settings" ("name", "value") VALUES ("thumbSize", "150");', @
          return undefined
          
      # read settings
      (err) ->
        if err then throw err
        db.all 'SELECT * FROM "Settings"', @
        return undefined

      # add to app settings
      (err, rows) ->
        if err then throw err
        if not rows then throw new Error('Unable to read application settings.')

        settings = cutil.joinObjects settings, rows
        app.set 'settings', settings

        # check folders
        cutil.fileExists settings.albumDir, @parallel()
        cutil.fileExists settings.thumbDir, @parallel()
        cutil.fileExists settings.uploadDir, @parallel()
        return undefined

      # create directories
      (err, albumsExists, thumbsExists, uploadsExists) ->
        if err then throw err
        if albumsExists and thumbsExists and uploadsExists then return null

        if not albumsExists then fs.mkdir settings.albumDir, 0755, @parallel()
        if not thumbsExists then fs.mkdir settings.thumbDir, 0755, @parallel()
        if not uploadsExists then fs.mkdir settings.uploadDir, 0755, @parallel()
        return undefined

      # create akismet client
      (err) ->
        if err then throw err

        if settings.akismetKey and settings.akismetURL
          akismetClient = akismet.client { apiKey: settings.akismetKey, blog: settings.akismetURL }
          app.set 'akismet', akismetClient
          akismetClient.verifyKey @
          return undefined
        else
          return null

      # end of config
      (err, verified) ->
        if err then throw err

        # check akismet
        if verified is true
          util.log 'Verified Akismet key'
        else if verified is false
          util.log 'Could not verify Akismet key.'
          app.set 'akismet', null
        else if verified is null
          util.log 'Akismet key does not exist.'
          app.set 'akismet', null

        # start upload monitor
        UploadMonitor = require './libs/monitor'
        monitor = new UploadMonitor(db, settings.albumDir, settings.thumbDir, settings.uploadDir, settings.thumbSize, settings.monitorInterval * 60 * 1000)
        monitor.start()
        app.set 'monitor', monitor

        # Stop upload monitor on exit
        process.on 'exit', () ->
          monitor.stop()

        # Default controller
        app.get '*', (req, res, next) ->
          app._locals.pageCount = 0
          app._locals.pagetitle = ''
          app._locals.album = null
          app._locals.picture = null
          next()

        # Include controllers
        for file in fs.readdirSync path.join(__dirname, 'controllers')
          filename = path.join __dirname, 'controllers', file
          if fs.statSync(filename).isFile()
            require filename

        # If no routes match fall to 404
        app.get '*', (req, res, next) ->
          res.render '404', {
              layout: false
            }

        # execute callback
        self.initialized = true
        callback err
    )


  # Run the application
  #
  # port: the port to listen, defaults to 80
  run: (port) ->
    port or= 80
    app = @expressApp

    if not @initialized
      @init (err) ->
        if err then throw err
        app.listen port
        util.log 'Application started.'
    else
      app.listen port
      util.log 'Application started.'


module.exports = new Application()

