import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { join, resolve, normalize } from 'node:path';

const root = resolve(process.argv[2] ?? 'build/web');
const host = process.argv[3] ?? '127.0.0.1';
const port = Number(process.argv[4] ?? 5175);

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

function contentType(path) {
  const ext = path.slice(path.lastIndexOf('.')).toLowerCase();
  return mimeTypes[ext] ?? 'application/octet-stream';
}

createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://${host}:${port}`);
  const requested = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, '');
  let filePath = resolve(join(root, requested));

  if (!filePath.startsWith(root)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  if (!existsSync(filePath) || statSync(filePath).isDirectory()) {
    filePath = join(root, 'index.html');
  }

  res.writeHead(200, {
    'Content-Type': contentType(filePath),
    'Cache-Control': 'no-store',
  });
  createReadStream(filePath).pipe(res);
}).listen(port, host, () => {
  console.log(`Serving ${root} at http://${host}:${port}`);
});
