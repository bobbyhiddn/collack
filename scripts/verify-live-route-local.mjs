#!/usr/bin/env node

import { createReadStream } from "node:fs";
import { createServer } from "node:http";
import { stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { verifyLiveRoute } from "../deploy/shore/verify-live-route.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const webRoot = path.join(root, "dist", "web");
const routePrefix = "/collack/";
const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".data": "application/octet-stream",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
};

const server = createServer(async (request, response) => {
  try {
    const requestUrl = new URL(request.url ?? routePrefix, "http://127.0.0.1");
    if (!requestUrl.pathname.startsWith(routePrefix)) {
      response.writeHead(404).end("Not found");
      return;
    }
    const relative = requestUrl.pathname === routePrefix
      ? "index.html"
      : decodeURIComponent(requestUrl.pathname.slice(routePrefix.length));
    const requestedPath = path.resolve(webRoot, relative);
    if (requestedPath !== webRoot && !requestedPath.startsWith(`${webRoot}${path.sep}`)) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    const info = await stat(requestedPath);
    if (!info.isFile()) throw new Error("not a file");
    const immutable = /\.[0-9a-f]{16}\.(?:js|data|wasm)$/.test(requestedPath);
    response.writeHead(200, {
      "Content-Type": contentTypes[path.extname(requestedPath)] ?? "application/octet-stream",
      "Content-Length": info.size,
      "Cache-Control": immutable ? "public, max-age=31536000, immutable" : "no-cache",
    });
    createReadStream(requestedPath).pipe(response);
  } catch {
    response.writeHead(404).end("Not found");
  }
});

try {
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("local route did not bind");
  await verifyLiveRoute({ routeUrl: `http://127.0.0.1:${address.port}${routePrefix}` });
} finally {
  await new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
}
