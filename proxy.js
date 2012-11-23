var httpProxy = require('http-proxy');

//
// Create a proxy server with custom application logic
//
httpProxy.createServer(function (req, res, proxy) {
  console.log(req.url)

  res.write('test');
  res.end();

  proxy.proxyRequest(req, res, {
    host: 'localhost',
    port: 8080
  });
}).listen(8000);