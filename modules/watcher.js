var fs = require('fs');
var path = require('path');

/**
 * Watcher
 */
function Watcher () {}

Watcher.prototype = {
  /**
   * Watch all files in derictory (recursive)
   * @param  {String}   root     root path
   * @param  {Function} callback
   * @param  {Object}   options  include, exclude files
   */
  watchTree: function (root, callback, options) {
    var files = []
      , timeouts = {};

    this.setFileListSync(root, files, options);
    
    files.forEach(function (file) {
      fs.watch(file, function (event, filename) {
        clearTimeout(timeouts[file]); // fix bug in windows with multiple events
        timeouts[file] = setTimeout(function () {
          callback.call(null, event, file)
        }, 100);
      });
    });
  },

  /**
   * Get recursive files from derctory
   * @param {String} root    root direcory
   * @param {Array}  output  ouput variable
   * @param {Object} options
   */
  setFileListSync: function(root, output, options) {
    var files = fs.readdirSync(root)
      , that = this
      , isOption = {}
      , file
      , stat

    files.forEach(function(item) {
      file = path.join(root, item);
      stat = fs.statSync(file);
      isOption.ext = options && options.ext ? options.ext.indexOf(path.extname(file)) >= 0 : true;
      isOption.excludeFolder = options && options.excludeFolder ? options.excludeFolder.indexOf(item) < 0 : true;

      if (stat.isFile() && isOption.ext) {
        output.push(file);
      } else if (stat.isDirectory() && isOption.excludeFolder) {
        that.setFileListSync(file, output, options);
      }
    });
  }
};

/**
 * Expose the root command.
 */
exports = module.exports = new Watcher;