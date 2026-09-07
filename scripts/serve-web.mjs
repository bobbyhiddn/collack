import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../dist/web/", import.meta.url));
const port = Number(process.env.PORT || 8080);
const mime = { ".html": "text/html; charset=utf-8", ".js": "application/javascript",
  ".wasm": "application/wasm", ".css": "text/css", ".json": "application/json", ".png": "image/png" };
export function createWebServer() {
  return createServer(async (request, response) => {
  try {
    const url = new URL(request.url, "http://localhost");
    const relative = decodeURIComponent(url.pathname);
    const file = path.resolve(root, relative === "/" ? "index.html" : `.${relative}`);
    if (!file.startsWith(root)) { response.writeHead(403).end(); return; }
    const info = await stat(file);
    if (!info.isFile()) throw new Error("Not a file");
    response.writeHead(200, { "Content-Type": mime[path.extname(file)] || "application/octet-stream",
      "Content-Length": info.size, "Cache-Control": "no-store" });
    createReadStream(file).pipe(response);
  } catch { response.writeHead(404).end("Not found"); }
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  createWebServer().listen(port, "127.0.0.1", () => {
    console.log(`Collack is ready at http://127.0.0.1:${port}`);
  });
}
