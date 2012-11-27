var fs = require('fs');
var watch = require('watch');

watch.createMonitor('.', function (monitor) {
  monitor.files['.'] // Stat object for my zshrc.
  monitor.on("created", function (f, stat) {
    console.log('created')
  })
  monitor.on("changed", function (f, curr, prev) {
    console.log('changed')
  })
  monitor.on("removed", function (f, stat) {
    console.log('removed')
  })
})