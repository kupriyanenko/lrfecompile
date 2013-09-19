fs = require 'fs'
path = require 'path'
http = require 'http'

watch = require 'watch'
moment = require 'moment'

changed =
  theme: {}
  portlet: {}
  extension: {}

log = () ->
  console.log moment().format('[[]h:mm:ss YYYY-D-MM[]]'), [].join.call arguments, ' '

class Watcher
  ###
  Watcher base class
  ###
  constructor: (config, options) ->
    @rootDir = path.join options.root, config.root
    @toCopyDir = path.join options.tomcat, config.tomcat
    @options = options;

    log "start watch folder #{@rootDir}" if not config.silence

  copyFile: (oldFile, newFile) ->
    ### Copy file from old directory to new derictory ###
    try
      stats = fs.lstatSync newFile

      if stats.isFile()
        printName = newFile
        newFile = fs.createWriteStream newFile
        oldFile = fs.createReadStream oldFile

        oldFile.addListener "data", (chunk) ->
          newFile.write chunk

        oldFile.addListener "close", =>
          newFile.end()
          log 'update', printName
    catch e
      log "copy file failed!, error: #{e}"

  watchTree: (root, callback) ->
    ### Watch tree files ###
    try
      stats = fs.lstatSync root

      if stats.isDirectory()
        watch.watchTree root, {
          interval: @options.interval
        }, (f, curr, prev) ->
          if typeof f is "object" and prev is null and curr is null
            # Finished walking the tree
          else if prev is null
            # f is a new file
          else if curr.nlink is 0
            # f was removed
          else
            # f was changed
            callback.call this, f, curr, prev
    catch e
      log "watch file failed!, error: #{e}"

  updateChanged: (type, url) ->
    ### Update proxy cache for file ###
    name = path.basename url
    changed[type][name] = new Date().getTime()

class PortletWatcher extends Watcher
  ###
  Watch changes files in portlets
  ###
  init: ->
    for portlet in @getPortletList()
      @watchTree path.join(@rootDir, portlet, 'docroot'), (filename, curr, prev) =>
        sep = if path.sep is '\\' then '\\\\' else path.sep
        
        regexName = new RegExp "^(.*?)portlets#{sep}(.*?)#{sep}(.*?)$", 'gi'
        portletName = path.dirname(filename).replace(regexName, '$2')
        regexPath = new RegExp "^(.*?)portlets#{sep}#{portletName}#{sep}docroot#{sep}(.*?)$", 'gi'
        folderPath = path.dirname(filename).replace(regexPath, '$2')

        toCopyFile = path.join @toCopyDir, portletName, folderPath, path.basename(filename)

        @copyFile filename, toCopyFile
        @updateChanged 'portlet', filename

  getPortletList: ->
    ### Get list with portlets name ###
    portlet for portlet in fs.readdirSync @rootDir when fs.statSync(path.join @rootDir, portlet).isDirectory()

class ExtensionWatcher extends Watcher
  ###
  Watch changes files in extensions
  ###
  init: ->
    @watchTree @rootDir, (filename, curr, prev) =>
      regexPath = new RegExp '^(.*?)html(.*?)$', 'gi'
      folderPath = filename.replace regexPath, '$2'
      toCopyFile = path.join @toCopyDir, folderPath

      @copyFile filename, toCopyFile
      @updateChanged 'extension', filename

class ThemeWatcher extends Watcher
  ###
  Watch changes files in themes
  ###
  init: ->
    for theme in @getThemeList()
      pathTheme = if theme isnt 'core' then 'docroot/_diffs' else ''
      log "start watch folder #{path.join @rootDir, theme, pathTheme}"
      @createWatcher path.join(@rootDir, theme, pathTheme), theme

  updateChanged: (name) ->
    ### Update proxy cache for file ###
    changed['theme'][name] = new Date().getTime()

  getThemeList: ->
    ### Get list with themes name ###
    theme for theme in fs.readdirSync @rootDir when fs.statSync(path.join @rootDir, theme).isDirectory()

  createWatcher: (root, theme) ->
    ### Create watcher for theme ###
    @watchTree root, (filename, curr, prev) =>
      if path.extname(filename) in ['.css', '.scss']
        folder = 'css'
      else if path.extname(filename) in ['.js', '.json', '.html']
        regexName = new RegExp "^(.*?)_diffs(.*?)$", 'gi'
        folder = path.dirname(filename).replace(regexName, '$2')
      else if path.extname(filename) in ['.vm']
        folder = 'templates'

      @copyToThemes filename, folder, theme if folder

  copyToThemes: (pathFile, folder, theme) ->
    ### Copy file to themes ###
    if theme is 'core'
      for themeName in @getThemeList()
        continue if themeName is 'core'

        if 'portlets' in pathFile.split path.sep
          toCopyFile = path.join @toCopyDir, themeName, folder, 'portlets', path.basename pathFile
          themeFile = path.join @rootDir, themeName, 'docroot/_diffs', folder, 'portlets', path.basename pathFile
        else
          toCopyFile = path.join @toCopyDir, themeName, folder, path.basename pathFile
          themeFile = path.join @rootDir, themeName, 'docroot/_diffs', folder, path.basename pathFile
        
        if not fs.existsSync themeFile
          @copyFile pathFile, toCopyFile 
          @updateChanged themeName
    else
      if 'portlets' in pathFile.split path.sep
        toCopyFile = path.join @toCopyDir, theme, folder, 'portlets', path.basename pathFile
      else
        toCopyFile = path.join @toCopyDir, theme, folder, path.basename pathFile
      @copyFile pathFile, toCopyFile 
      @updateChanged theme


### Exports ###

module.exports = (options) ->
  ###
  Init script
  ###
  portlets = new PortletWatcher {
    root: './portlets'
    tomcat: './webapps'
  }, options
  extensions = new ExtensionWatcher {
    root: './ext/platform-ext/docroot/WEB-INF/ext-web/docroot/html'
    tomcat: './webapps/ROOT/html'
  }, options
  themes = new ThemeWatcher {
    root: './themes'
    tomcat: './webapps'
    silence: true
  }, options

  # Init watchers
  portlets.init()
  extensions.init()
  themes.init()

  # Get content lists
  portletList = portlets.getPortletList()
  themeList = themes.getThemeList()

  server = http.createServer (request, response) ->
    ###
    Create proxy server
    ###
    getType = (url) ->
      ### Get file type (portlet, theme, extension) ###
      url = url.split '/'

      for segment in url
        if segment in portletList
          return 'portlet'
        else if segment in themeList
          return 'theme'
        else if segment is 'html'
          return 'extension'

    getName = (url, type) ->
      ### Get name for cached file ###
      if type is 'theme'
        return segment for segment in url.split('/') when segment in themeList
      else
        path.basename url

    getPath = ->
      ### Get hash for url ###
      url = if (index = request.url.indexOf('?')) >= 0 then request.url.substring 0, index else request.url
      type = getType url

      if type
        name = getName url, type
        stamp = changed[type][name] ? changed[type][name] = new Date().getTime()
        hash = if index >= 0 then "&proxy_hash=#{stamp}" else "?proxy_hash=#{stamp}"
        request.url + hash
      else
        request.url

    config =
      port: options.liferayport,
      host: request.host,
      method: request.method,
      path: getPath(),
      headers: request.headers

    proxy = http.request config, (res) ->
      res.on 'data', (chunk) ->
        response.write chunk, 'binary'
      res.on 'end', ->
        response.end()

      response.writeHead res.statusCode, res.headers

    request.on 'data', (chunk) ->
      proxy.write chunk, 'binary'
    request.on 'end', ->
      proxy.end()

  server.listen options.proxyport

  server.on 'error', (err) ->
    log 'there was an error:', err.message
