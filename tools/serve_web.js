// Servidor estático mínimo para probar el panel web compilado:
//   flutter build web  →  node tools/serve_web.js  →  http://localhost:8787
const http = require("http"), fs = require("fs"), path = require("path");
const root = path.resolve(__dirname, "..", "bookingnow_app", "build", "web");
const port = Number(process.env.PORT || 8787);
const types = { ".html": "text/html", ".js": "application/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".ico": "image/x-icon", ".wasm": "application/wasm", ".otf": "font/otf", ".ttf": "font/ttf", ".svg": "image/svg+xml" };
http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split("?")[0]);
  let file = path.join(root, p);
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, "index.html");
  res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
}).listen(port, () => console.log(`Panel web en http://localhost:${port}`));
