/*!
 * JavaScript template precompiler
 * Copyright(c) 2012 Alexey Kupriyanenko <a.kupriyanenko@gmail.com>
 * MIT Licensed
 */

var fs = require('fs');
var walk = require('walk');
var options = require('commander');
var watchTree = require("fs-watch-tree").watchTree;
var path = require('path');
var http = require('http');

// Get options
options
  .version('0.0.1')
  .option('-r, --root <n>', 'plugins folder', '.')
  .option('-t, --tomcat <n>', 'tomcat folder')
  .option('-l, --liferayport <n>', 'liferay port', 8080)
  .option('-p, --proxyport <n>', 'liferay port', 8000)
  .parse(process.argv);

if (!options.tomcat)
  options.help();

// global config
var config = {
  changed: {
    theme: {},
    portlet: {},
    extension: {},
  }
}

/**
 * Copy file
 * @param  {String} oldFile
 * @param  {String} newFile
 */
function copyFile(oldFile, newFile) {
  var printName = newFile;
  var newFile = fs.createWriteStream(newFile);     
  var oldFile = fs.createReadStream(oldFile);

  oldFile.addListener("data", function(chunk) {
    newFile.write(chunk);
  })

  oldFile.addListener("close", function() {
    newFile.end();
    console.log('update', printName);
  });
}

/**
 * Watch portlets
 */
function watchPortlet() {
  console.log('start watch portlets...');

  var rootDir = path.join(options.root, './portlets')
    , toCopyDir = path.join(options.tomcat, './webapps');

  /**
   * Check approved extension
   * @param  {String} ext
   * @return {Boolean}
   */
  var checkExt = function(ext) {
    var extensions = ['.css', '.scss', '.vm', '.js', '.jsp', '.jspf'];

    if (extensions.indexOf(ext) !== -1)
      return true;

    return false;
  }

  watchTree(rootDir, function (event) {
    if (!checkExt(path.extname(event.name)))
      return;

    var separator = path.sep == '\\' ? '\\\\' : path.sep
      , regexName = new RegExp('^(.*?)portlets' + separator + '(.*?)' + separator + '(.*?)$', 'gi')
      , portletName = path.dirname(event.name).replace(regexName, "$2")
      , regexPath = new RegExp('^(.*?)portlets' + separator + portletName + separator + 'docroot'+ separator  + '(.*?)$', 'gi')
      , folderPath = path.dirname(event.name).replace(regexPath, "$2")
      , toCopyFile = path.join(toCopyDir, portletName, folderPath, path.basename(event.name));

  	copyFile(event.name, toCopyFile)
  });
}

/**
 * Watch extensions
 */
function watchExtension() {
  console.log('start watch extensions...');

  var rootDir = path.join(options.root, './ext/platform-ext/docroot/WEB-INF/ext-web/docroot/html')
    , toCopyDir = path.join(options.tomcat, './webapps/ROOT/html');

  watchTree(rootDir, function (event) {
    var regexPath = new RegExp('^(.*?)html(.*?)$', 'gi')
      , folderPath = event.name.replace(regexPath, "$2")
      , toCopyFile = path.join(toCopyDir, folderPath);

    copyFile(path.normalize(event.name), toCopyFile);
    config.changed.extension[path.basename(event.name)] = new Date().getTime();
  });
}

/**
 * Watch themes
 */
function watchTheme() {
  console.log('start watch themes...');

  var rootDir = path.join(options.root, './themes')
    , toCopyDir = path.join(options.tomcat, './webapps')
    , themeList = [];

  fs.readdirSync(rootDir).forEach(function(name) {
    var stat = fs.statSync(path.join(rootDir, name));
    if (stat.isDirectory())
      themeList.push(name)
  });

  /**
   * Copy file to themes
   * @param  {String} pathFile
   * @param  {String} folder
   * @param  {String} theme
   */
  var copyToThemes = function(pathFile, folder, theme) {
    var themeFile
      , toCopyFile;

    // if theme is core, check override file in custom theme or not
    if (theme == 'core') {
      themeList.forEach(function(themeName) {
        // each only custom themes
        if (themeName == 'core')
          return;

        if (pathFile.slice(path.sep).indexOf('portlets') !== -1) {
          toCopyFile = path.join(toCopyDir, themeName, folder, 'portlets', path.basename(pathFile));
          themeFile = path.join(rootDir, themeName, 'docroot/_diffs', folder, 'portlets', path.basename(pathFile));
        } else {
          toCopyFile = path.join(toCopyDir, themeName, folder, path.basename(pathFile));
          themeFile = path.join(rootDir, themeName, 'docroot/_diffs', folder, path.basename(pathFile));
        }

        if (!fs.existsSync(themeFile))
          copyFile(pathFile, toCopyFile);
      });
    } else {
      toCopyFile = path.join(toCopyDir, theme, folder, path.basename(pathFile));
      copyFile(pathFile, toCopyFile);
    }
  }

  /**
   * Create watcher for theme
   * @param  {String} root
   * @param  {String} theme
   */
  var createWatcher = function(root, theme) {
    watchTree(root, function (event) {
      var folder;

      if (['.css', '.scss'].indexOf(path.extname(event.name)) !== -1) {
        folder = 'css';
      } else if (['.js', '.json'].indexOf(path.extname(event.name)) !== -1) {
        folder = 'js';
      } else if (['.vm'].indexOf(path.extname(event.name)) !== -1) {
        folder = 'templates';
      }

      if (folder)
        copyToThemes(event.name, folder, theme);
    });
  }

  themeList.forEach(function(theme) {
    createWatcher(path.join(rootDir, theme), theme);
  });
}

/**
 * Create proxy server
 */
function createProxy() {
  http.createServer(function(request, response) {
    var proxyHash = '&proxy=' + new Date().getTime();
    proxyHash = '';

    var config = {
      port: options.liferayport,
      host: request.host,
      method: request.method,
      path: request.url + proxyHash,
      headers: request.headers
    };

    console.log(request.url)

    var proxy = http.request(config, function(res) {
      res.on('data', function(chunk) {
        response.write(chunk, 'binary');
      });
      res.on('end', function() {
        response.end();
      });

      response.writeHead(res.statusCode, res.headers);
    });
   
    request.on('data', function(chunk) {
      proxy.write(chunk, 'binary');
    });

    request.on('end', function() {
      proxy.end();
    });
  }).listen(options.proxyport);
}

// Init
watchPortlet();
watchExtension();
watchTheme();
createProxy();