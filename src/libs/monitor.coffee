path = require 'path'
fs = require 'fs'
step = require 'step'
sqlite = require 'sqlite'
util = require 'util'
cutil = require './util'
im = require './img'


class UploadMonitor


  # Creates a new upload monitor
  #
  # db: database connection object
  # albumDir: path to album directory
  # thumbDir: path to thumbnail directory
  # uploadDir: path to uploads directory
  # thumbSize: size of generated thumbnails
  # watchInterval: time in milliseconds between new album checks
  constructor: (db, albumDir, thumbDir, uploadDir, thumbSize, watchInterval) ->
    @db = db
    @albumDir = albumDir
    @thumbDir =  thumbDir
    @uploadDir =  uploadDir
    @thumbSize = thumbSize
    @watchInterval = watchInterval


  # Starts watching the uploads folder
  start: () ->
    @stopWatching = false
    setTimeout @watchUploads(), @watchInterval
    util.log 'Upload monitor started.'


  # Stops watching the uploads folder
  stop: () ->
    @stopWatching = true
    util.log 'Upload monitor stopped.'

  # Watches the uploads folder for new pictures
  watchUploads: () ->

    self = @
    if self.readingAlbums and not self.stopWatching
      setTimeout self.watchUploads(), self.watchInterval
      return
    self.readingAlbums = true
    albums = []

    step(

      # move pictures in root folder
      () ->
        self.moveRootPictures @
        return undefined

      # get albums
      (err) ->
        if err then throw err
        self.readUploads @
        return undefined

      # save albums
      (err, newalbums) ->
        if err then throw err
        albums = newalbums
        if albums.length is 0 then return null

        albumSQL = 'INSERT INTO "Albums" ("name", "dateCreated") VALUES (?, ?)'
        pictureSQL = 'INSERT INTO "Pictures" ("name", "dateTaken", "album") VALUES (?, ?, ?)'

        group = @group()
        for album in albums
          self.db.execute albumSQL, [album.name, cutil.dateToSQLite(album.dateCreated)], group()

          for picture in album.pictures
            self.db.execute pictureSQL, [picture.name, cutil.dateToSQLite(picture.dateTaken), album.name], group()

        return undefined

      # check directories
      (err) ->
        if err then throw err
        if albums.length is 0 then return []
        group = @group()
        for album in albums
          cutil.fileExists path.join(self.albumDir, album.name), group()
        return undefined

      # make directories
      (err, exists) ->
        if err then throw err
        if exists.length is 0 then return null
        group = @group()
        for i in [0...albums.length]
          if not exists[i]
            fs.mkdir path.join(self.albumDir, albums[i].name), 0755, group()
        return undefined
 
      # move albums
      (err) ->
        if err then throw err
        if albums.length is 0 then return null
        group = @group()
        for album in albums
          for picture in album.pictures
            fs.rename path.join(self.uploadDir, album.name, picture.name), path.join(self.albumDir, album.name, picture.name), group()
        return undefined
       
      # delete upload folders
      (err) ->
        if err then throw err
        if albums.length is 0 then return null
        group = @group()
        for album in albums
          fs.rmdir path.join(self.uploadDir, album.name), @
        return undefined

      # done
      (err) ->
        if err then throw err
        self.readingAlbums = false
        if not self.stopWatching
          setTimeout self.watchUploads(), self.watchInterval
    )


  # Reads and returns albums from the filesystem
  #
  # callback: err, array of album objects
  readUploads: (callback) ->

    callback = cutil.ensureCallback callback
    self = @
    root = @uploadDir

    step(

      # read directories
      () ->
        fs.readdir root, @
        return undefined

      # build albums
      (err, dirNames) ->
        if err then throw err
        if dirNames? and dirNames.length is 0 then return []
        group = @group()
        for dirName in dirNames
          dir = path.join root, dirName
          if fs.statSync(dir).isDirectory()
            self.readAlbumFromFS dir, group()
        return undefined

      # return albums
      (err, albums) ->
        if err then throw err
        newalbums = []
        for album in albums
          if album.pictures.length isnt 0 then newalbums.push album
        callback err, newalbums

    )


  # Moves pictures in root upload folder into their own album folders
  #
  # callback: err
  moveRootPictures: (callback) ->

    callback = cutil.ensureCallback callback
    self = @
    root = @uploadDir
    pictures = []

    step(

      # read files
      () ->
        fs.readdir root, @
        return undefined

      # read date taken
      (err, fileNames) ->
        if err then throw err
        group = @group()
        for fileName in fileNames
          file = path.join root, fileName
          if fs.statSync(file).isFile()
            pictures.push { name: fileName, source: file }
            im.getDate file, group()
        if pictures.length is 0 then return []
        return undefined

      # check directories
      (err, dates) ->
        if err then throw err
        if dates? and dates.length is 0 then return []
        if not dates or dates.length isnt pictures.length then throw 'Error reading root picture dates from file system.'
        group = @group()
        for i in [0...dates.length]
          dir = path.join root, cutil.dateToSQLite(dates[i], false)
          pictures[i].destDir = dir
          pictures[i].dest = path.join dir, pictures[i].name
          cutil.fileExists dir, group()
        return undefined

      # make directories
      (err, exists) ->
        if err then throw err
        if exists? and exists.length is 0 then return []
        group = @group()
        for i in [0...pictures.length]
          if not exists[i]
            fs.mkdir pictures[i].destDir, 0755, group()
        return undefined
      
      # move pictures
      (err) ->
        if err then throw err
        if pictures.length is 0 then return null
        group = @group()
        for picture in pictures
          fs.rename picture.source, picture.dest, group()
        return undefined

      # execute callback
      (err) ->
        if err then throw err
        callback err

    )


  # Reads and returns an album from the filesystem
  #
  # root: path to album directory
  # callback: err, album object
  readAlbumFromFS: (root, callback) ->

    callback = cutil.ensureCallback callback
    self = @
    album = {}

    step(

      # read directory
      () ->
        fs.readdir root, @
        return undefined
        
      # save pictures
      (err, fileNames) ->
        if err then throw err

        albumName = path.basename root
        pics = []
        for fileName in fileNames
          file = path.join root, fileName
          if fs.statSync(file).isFile()
            pic = {
              name: fileName
            }
            pics.push pic

        album = {
          name: albumName
          pictures: pics
          dateCreated: new Date()
        }

        if album.pictures.length is 0 then return null

        # create thumbnails
        im.makeAllThumbnails root, path.join(self.thumbDir, album.name), self.thumbSize, @
        return undefined

      # read date taken
      (err) ->
        if err then throw err
        if album.pictures.length is 0 then return []
        group = @group()
        for pic in album.pictures
          im.getDate path.join(root, pic.name), group()
        return undefined

      # save date taken
      (err, dates) ->
        if err then throw err
        if not dates or dates.length isnt album.pictures.length then throw 'Error reading album ' + album.name + ' from file system.'

        for i in [0...dates.length]
          album.pictures[i].dateTaken = dates[i]

        callback err, album
    )


module.exports = UploadMonitor

