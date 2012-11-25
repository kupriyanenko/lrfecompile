lrfecompile
=======

A node.js module for automatic compile frontend on [Liferay](http://www.liferay.com/).

Just run the script, and all changes in portlets, extensions and themes will be immediately available for viewing.

Script monitors the following folders:

```
./portlets
./ext/platform-ext/docroot/WEB-INF/ext-web/docroot/html
./themes
```

### Installation ###

To install, first make sure you have a working copy of the latest stable version of [Node.js](http://nodejs.org/), and [npm](https://npmjs.org/) (the Node Package Manager). You can then install lrfecompile with npm:

    $ npm install lrfecompile -g


### Usage ###

lrfecompile can be run from the command line:

```
Usage: lrfecompile [options]

Options:

  -h, --help             output usage information
  -V, --version          output the version number
  -t, --tomcat <n>       tomcat root folder
  -r, --root <n>         plugins root folder, defaul '.'
  -l, --liferayport <n>  liferay port, defaul 8080
  -p, --proxyport <n>    proxy port, defaul 8000

Examples:

  $ lrfecompile -t ../liferay-portal-6.1.1-ce-ga2/tomcat-7.0.27/ -p 9000
```

Then your portal will be available at the new port (proxyport), fox ex:

    http://portal.dev:9000

### Be happy ###

Use it, fork it.
