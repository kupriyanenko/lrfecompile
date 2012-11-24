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

config =
  changed:
    theme: {}
    portlet: {}
    extension: {}

copyFile = (oldFile, newFile) ->
  ###
  Copy file from old directory to new derictory
  ###
  printName = newFile
  newFile = fs.createWriteStream newFile
  oldFile = fs.createReadStream oldFile

  oldFile.addListener "data", (chunk) ->
    newFile.write chunk

  oldFile.addListener "close", ->
    newFile.end()
    console.log 'update', printName

watchPortlet = ->
  ###
  Watch changes files in portlets
  ###
  rootDir = path.join options.root, './portlets'
  toCopyDir = path.join options.tomcat, './webapps'

  console.log "start watch folder #{rootDir}"

  for portlet in fs.readdirSync rootDir when fs.statSync(path.join rootDir, name).isDirectory()
    watchTree path.join(rootDir, portlet, 'docroot'), {exclude: ['WEB-INF']}, (event) ->
      sep = if path.sep is '\\' then '\\\\' else path.sep
      regexName = new RegExp "^(.*?)portlets#{sep}(.*?)#{sep}(.*?)$", 'gi'
      portletName = path.dirname(event.name).replace(regexName, "$2")
      
      regexPath = new RegExp "^(.*?)portlets#{sep}#{portletName}#{sep}docroot#{sep}(.*?)$", 'gi'
      folderPath = path.dirname(event.name).replace(regexPath, "$2")
      toCopyFile = path.join toCopyDir, portletName, folderPath, path.basename(event.name)

      copyFile event.name, toCopyFile

watchExtension = ->
  ###
  Watch changes files in extensions
  ###
  rootDir = path.join options.root, './ext/platform-ext/docroot/WEB-INF/ext-web/docroot/html'
  toCopyDir = path.join options.tomcat, './webapps/ROOT/html'

  console.log "start watch folder #{rootDir}"

  watchTree rootDir, (event) ->
    regexPath = new RegExp '^(.*?)html(.*?)$', 'gi'
    folderPath = event.name.replace regexPath, "$2"
    toCopyFile = path.join toCopyDir, folderPath

    copyFile event.name, toCopyFile

watchTheme = ->
  ###
  Watch changes files in themes
  ###
  rootDir = path.join options.root, './themes'
  toCopyDir = path.join options.tomcat, './webapps'
  themeList = []

  themeList = (name for name in fs.readdirSync rootDir when fs.statSync(path.join rootDir, name).isDirectory())

  copyToThemes = (pathFile, folder, theme) ->
    ###
    Copy file to themes
    ###
    if theme is 'core'
      for themeName in themeList
        if themeName is 'core'
          continue

        if pathFile.slice(path.sep).indexOf('portlets') isnt -1
          toCopyFile = path.join toCopyDir, themeName, folder, 'portlets', path.basename pathFile
          themeFile = path.join rootDir, themeName, 'docroot/_diffs', folder, 'portlets', path.basename pathFile
        else
          toCopyFile = path.join toCopyDir, themeName, folder, path.basename pathFile
          themeFile = path.join rootDir, themeName, 'docroot/_diffs', folder, path.basename pathFile

        copyFile pathFile, toCopyFile if not fs.existsSync themeFile
    else
      toCopyFile = path.join toCopyDir, theme, folder, path.basename pathFile
      copyFile pathFile, toCopyFile

  createWatcher = (root, theme) ->
    ###
    Create watcher for theme
    ###
    watchTree root, (event) ->
      if ['.css', '.scss'].indexOf(path.extname event.name) isnt -1
        folder = 'css'
      else if ['.js', '.json'].indexOf(path.extname event.name) isnt -1
        folder = 'js'
      else if ['.vm'].indexOf(path.extname event.name) isnt -1
        folder = 'templates'

      copyToThemes event.name, folder, theme if folder

  for theme in themeList
    pathTheme = if theme isnt 'core' then 'docroot/_diffs' else ''
    console.log "start watch folder #{path.join rootDir, theme, pathTheme}"
    createWatcher path.join(rootDir, theme, pathTheme), theme

createProxy = ->
  ###
  Create proxy server
  ###
  server = http.createServer (request, response) ->
    proxyHash = false

    config =
      port: options.liferayport,
      host: request.host,
      method: request.method,
      path: request.url + proxyHash,
      headers: request.headers

    proxy = http.request config, (res) ->
      res.on 'data', (chunk) ->
        response.write chunk, 'binary'
      res.on 'end', ->
        response.end()

      response.writeHead res.statusCode, res.headers

    request.on 'data', chunk ->
      proxy.write chunk, 'binary'

    request.on 'end', ->
      proxy.end()

  server.listen options.proxyport

# Init
watchPortlet()
watchExtension()
watchTheme()
createProxy()