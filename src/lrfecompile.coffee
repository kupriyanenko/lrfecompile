fs = require 'fs'
path = require 'path'
http = require 'http'

options = require 'commander'
watchTree = require('fs-watch-tree').watchTree

options
  .version('0.0.1')
  .option('-t, --tomcat <n>', 'tomcat folder')
  .option('-r, --root <n>', 'plugins folder', '.')
  .option('-l, --liferayport <n>', 'liferay port', 8080)
  .option('-p, --proxyport <n>', 'liferay port', 8000)
  .parse(process.argv)

options.help() if not options.tomcat

changed =
  theme: {}
  portlet: {}
  extension: {}

class Watcher
  ###
  Watcher base class
  ###
  constructor: (config) ->
    @rootDir = path.join options.root, config.root
    @toCopyDir = path.join options.tomcat, config.tomcat

    console.log "start watch folder #{@rootDir}" if not config.silence

  copyFile: (oldFile, newFile) ->
    ### Copy file from old directory to new derictory ###
    printName = newFile
    newFile = fs.createWriteStream newFile
    oldFile = fs.createReadStream oldFile

    oldFile.addListener "data", (chunk) ->
      newFile.write chunk

    oldFile.addListener "close", =>
      newFile.end()
      console.log 'update', printName

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
      watchTree path.join(@rootDir, portlet, 'docroot'), {exclude: ['WEB-INF']}, (event) =>
        sep = if path.sep is '\\' then '\\\\' else path.sep
        
        regexName = new RegExp "^(.*?)portlets#{sep}(.*?)#{sep}(.*?)$", 'gi'
        portletName = path.dirname(event.name).replace(regexName, '$2')
        regexPath = new RegExp "^(.*?)portlets#{sep}#{portletName}#{sep}docroot#{sep}(.*?)$", 'gi'
        folderPath = path.dirname(event.name).replace(regexPath, '$2')

        toCopyFile = path.join @toCopyDir, portletName, folderPath, path.basename(event.name)

        @copyFile event.name, toCopyFile
        @updateChanged 'portlet', event.name

  getPortletList: ->
    ### Get list with portlets name ###
    portlet for portlet in fs.readdirSync @rootDir when fs.statSync(path.join @rootDir, portlet).isDirectory()

class ExtensionWatcher extends Watcher
  ###
  Watch changes files in extensions
  ###
  init: ->
    watchTree @rootDir, (event) =>
      regexPath = new RegExp '^(.*?)html(.*?)$', 'gi'
      folderPath = event.name.replace regexPath, '$2'
      toCopyFile = path.join @toCopyDir, folderPath

      @copyFile event.name, toCopyFile
      @updateChanged 'extension', event.name

class ThemeWatcher extends Watcher
  ###
  Watch changes files in themes
  ###
  init: ->
    for theme in @getThemeList()
      console.log "start watch folder #{path.join @rootDir, theme, pathTheme}"
      pathTheme = if theme isnt 'core' then 'docroot/_diffs' else ''
      @createWatcher path.join(@rootDir, theme, pathTheme), theme

  updateChanged: (name) ->
    ### Update proxy cache for file ###
    changed['theme'][name] = new Date().getTime()

  getThemeList: ->
    ### Get list with themes name ###
    theme for theme in fs.readdirSync @rootDir when fs.statSync(path.join @rootDir, theme).isDirectory()

  createWatcher: (root, theme) ->
    ### Create watcher for theme ###
    watchTree root, (event) =>
      if path.extname(event.name) in ['.css', '.scss']
        folder = 'css'
      else if path.extname(event.name) in ['.js', '.json']
        folder = 'js'
      else if path.extname(event.name) in ['.vm']
        folder = 'templates'

      @copyToThemes event.name, folder, theme if folder

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
      toCopyFile = path.join @toCopyDir, theme, folder, path.basename pathFile
      @copyFile pathFile, toCopyFile 
      @updateChanged theme

createProxy = (proxyport, liferayport) ->
  ###
  Create proxy server
  ###
  server = http.createServer (request, response) ->
    portletsList = portlets.getPortletList()
    themesList = themes.getThemeList()

    getType = (url) ->
      ### Get file type (portlet, theme, extension) ###
      url = url.split(path.sep)

      for segment in url
        if segment in portletsList
          return 'portlet'
        else if segment in themesList
          return 'theme'
        else if segment is 'html'
          return 'extension'

    getName = (url, type) ->
      ### Get name for cached file ###
      if type is 'theme'
        return segment for segment in url.split(path.sep) when segment in themesList
      else
        path.basename(url)

    hash = (url) ->
      ### Get hash for url ###
      url = url.substring 0, index if (index = url.indexOf('?')) >= 0
      type = getType url
      name = getName url, type

      if type
        stamp = changed[type][name] ? changed[type][name] = new Date().getTime()
        if index >= 0 then "&proxy=#{stamp}" else "?proxy=#{stamp}"

    config =
      port: liferayport,
      host: request.host,
      method: request.method,
      path: if hash request.url then request.url + hash request.url else request.url,
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

  server.listen proxyport

###
Init script 
###
portlets = new PortletWatcher {
  root: './portlets'
  tomcat: './webapps'
}
extensions = new ExtensionWatcher {
  root: './ext/platform-ext/docroot/WEB-INF/ext-web/docroot/html'
  tomcat: './webapps/ROOT/html'
}
themes = new ThemeWatcher {
  root: './themes'
  tomcat: './webapps'
  silence: true
}

portlets.init()
extensions.init()
themes.init()

createProxy options.proxyport, options.liferayport