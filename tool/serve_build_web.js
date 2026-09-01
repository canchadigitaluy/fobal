const http = require('http');
const fs = require('fs');
const path = require('path');

const port = Number(process.env.PORT || 5180);
const root = path.resolve(__dirname, '..', 'build', 'web');
const types = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
};

http
  .createServer((req, res) => {
    let route = decodeURIComponent(req.url.split('?')[0]);
    if (route === '/' || route === '') route = '/index.html';

    let file = path.join(root, route);
    if (!file.startsWith(root)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    fs.stat(file, (statError, stat) => {
      if (statError || !stat.isFile()) file = path.join(root, 'index.html');

      fs.readFile(file, (readError, data) => {
        if (readError) {
          res.writeHead(404);
          res.end('Not found');
          return;
        }

        res.writeHead(200, {
          'content-type': types[path.extname(file)] || 'application/octet-stream',
        });
        res.end(data);
      });
    });
  })
  .listen(port, '127.0.0.1', () => {
    console.log(`Serving ${root} at http://127.0.0.1:${port}`);
  });
