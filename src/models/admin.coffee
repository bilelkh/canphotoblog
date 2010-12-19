util = require 'util'
fs = require 'fs'
path = require 'path'
step = require 'step'
akismet = require 'akismet'
cutil = require '../libs/util'


class Admin


  # Creates a new Admin object
  #
  # db: database connection object
  constructor: (db) ->
    @db = db


  # Saves and applies settings
  #
  # app: the application object to apply settings to
  # appName: application name
  # appTitle: application title
  # monitorInterval: interval between upload monitor checks
  # callback: err
  changeAppSettings: (app, appName, appTitle, monitorInterval, callback) ->

    callback = cutil.ensureCallback callback
    self = @

    step(

      # save settings
      () ->
        settings = app.set 'settings'
        settings.appName = appName
        settings.appTitle = appTitle
        settings.monitorInterval = monitorInterval
        app.set 'settings', settings

        monitor = app.set 'monitor'
        monitor.watchInterval = monitorInterval * 60 * 1000
        monitor.restart()

        group = @group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [appName, 'appName'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [appTitle, 'appTitle'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [monitorInterval, 'monitorInterval'], group()
        return undefined

      # execute callback
      (err) ->
        if err then throw err
        callback err

    )


  # Saves and applies view settings
  #
  # app: the application object to apply settings to
  # albumsPerPage: number of albums to show per page
  # picturesPerPage: number of pictures to show per page
  # thumbSize: thumbnail size
  # callback: err
  changeViewSettings: (app, albumsPerPage, picturesPerPage, thumbSize, callback) ->

    callback = cutil.ensureCallback callback
    self = @

    step(

      # save settings
      () ->
        settings = app.set 'settings'
        settings.albumsPerPage= albumsPerPage
        settings.picturesPerPage = picturesPerPage
        settings.thumbSize = thumbSize
        app.set 'settings', settings

        group = @group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [albumsPerPage, 'albumsPerPage'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [picturesPerPage, 'picturesPerPage'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [thumbSize, 'thumbSize'], group()
        return undefined

      # execute callback
      (err) ->
        if err then throw err
        callback err

    )


  # Saves and applies comment settings
  #
  # app: the application object to apply settings to
  # allowComments: true to allow comments
  # akismetKey: Akismet API Key
  # akismetURL: Akismet blog URL
  # callback err, verified (true if Akismet verified)
  changeCommentSettings: (app, allowComments, akismetKey, akismetURL, callback) ->

    callback = cutil.ensureCallback callback
    self = @
    akismetClient = null

    step(

      # save settings
      () ->
        settings = app.set 'settings'
        settings.allowComments = allowComments
        settings.akismetKey = akismetKey
        settings.akismetURL = akismetURL
        app.set 'settings', settings

        group = @group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [allowComments, 'allowComments'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [akismetKey, 'akismetKey'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [akismetURL, 'akismetURL'], group()
        return undefined

      # create akismet client
      (err) ->
        if err then throw err

        if akismetKey and akismetURL
          akismetClient = akismet.client { apiKey: akismetKey, blog: akismetURL }
          akismetClient.verifyKey @
          return undefined
        else
          return null
        return undefined

      # verify akismet client
      (err, verified) ->
        if err then throw err
        if not verified
          akismetClient = null
        app.set 'akismet', akismetClient

        callback err, verified

    )


  # Saves and applies analytics settings
  #
  # app: the application object to apply settings to
  # gaKey: Google Analytics key
  # callback err
  changeAnalyticsSettings: (app, gaKey, callback) ->

    callback = cutil.ensureCallback callback
    self = @

    step(

      # save settings
      () ->
        settings = app.set 'settings'
        settings.gaKey = gaKey
        app.set 'settings', settings

        group = @group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [gaKey, 'gaKey'], group()
        return undefined

      # execute callback
      (err) ->
        if err then throw err
        callback err

    )


  # Gets a list of background images
  #
  # app: the application object
  # callback: err, array of image names
  getBackgrounds: (app, callback)->

    dir = path.join app.set('settings').publicDir, 'img', 'backgrounds'
    self = @

    step(

      # get folder contents
      () ->
        fs.readdir dir, @
        return undefined

      # execute callback
      (err, fileNames) ->
        if err then throw err

        files = []
        for fileName in fileNames
          if path.extname(fileName).toLowerCase() is '.jpg'
            files.push fileName
        files.sort()
 
        callback err, files

    )


  # Gets a list of styles
  #
  # app: the application object
  # callback: err, array of image names
  getStyles: (app, callback)->

    dir = path.join app.set('settings').publicDir, 'css'
    self = @

    step(

      # get folder contents
      () ->
        fs.readdir dir, @
        return undefined

      # execute callback
      (err, fileNames) ->
        if err then throw err

        files = []
        for fileName in fileNames
          if path.extname(fileName).toLowerCase() is '.css'
            if fileName.toLowerCase() isnt 'default.css'
              files.push fileName
        files.sort()
 
        callback err, files

    )


  # Saves and applies style settings
  #
  # app: the application object to apply settings to
  # style: stylesheet
  # bgcolor: background color
  # bgimage: background image
  # callback err
  changeStyle: (app, style, bgcolor, bgimage, callback) ->

    callback = cutil.ensureCallback callback
    self = @

    step(

      # save settings
      () ->
        settings = app.set 'settings'
        settings.style = style
        settings.backgroundColor = bgcolor
        settings.backgroundImage = bgimage
        app.set 'settings', settings

        group = @group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [style, 'style'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [bgcolor, 'backgroundColor'], group()
        self.db.execute 'UPDATE "Settings" SET "value"=? WHERE "name"=?', [bgimage, 'backgroundImage'], group()
        return undefined

      # execute callback
      (err) ->
        if err then throw err
        callback err

    )


module.exports = Admin

