#!/usr/bin/env node
//
// A mirror that fails on purpose, for the retry tests: it serves the files under <root> over HTTP,
// but a request for <root>/<path> first gets what <root>/<path>.plan holds. A plan has one line
// per answer still to give, each a status ("504"), a method and a status ("HEAD 504"), or "drop"
// to close the connection without answering. The first line is used up by the next request it
// applies to; once the plan is empty, the file is served. Every request is appended to
// <root>/requests.log as "<method> <path> <status>".
//
// Usage: node flaky-mirror.js <root> <port-file>
// Listens on a free port of 127.0.0.1, and writes that port to <port-file> once it is ready.

"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");

const [root, portFile] = process.argv.slice(2);

// The answer the plan holds for this request, if any, using it up.
function planned(file, method) {
  const planFile = `${file}.plan`;
  if (!fs.existsSync(planFile)) return null;
  const lines = fs.readFileSync(planFile, "utf8").split("\n").filter((line) => line.trim() !== "");
  if (lines.length === 0) return null;
  const words = lines[0].trim().split(/\s+/);
  const [forMethod, answer] = words.length === 1 ? [null, words[0]] : words;
  if (forMethod !== null && forMethod !== method) return null;
  fs.writeFileSync(planFile, lines.slice(1).map((line) => `${line}\n`).join(""));
  return answer;
}

const server = http.createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, "http://127.0.0.1").pathname);
  const file = path.join(root, pathname);
  const log = (status) => fs.appendFileSync(path.join(root, "requests.log"), `${request.method} ${pathname} ${status}\n`);

  const answer = planned(file, request.method);
  if (answer === "drop") {
    log("drop");
    request.socket.destroy();
    return;
  }
  if (answer !== null) {
    log(answer);
    response.writeHead(Number(answer), { "Content-Type": "text/plain" });
    response.end(request.method === "HEAD" ? undefined : `${answer}\n`);
    return;
  }

  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
    log(404);
    response.writeHead(404, { "Content-Type": "text/plain" });
    response.end(request.method === "HEAD" ? undefined : "404\n");
    return;
  }
  log(200);
  const body = fs.readFileSync(file);
  response.writeHead(200, { "Content-Length": body.length, "Content-Type": "application/octet-stream" });
  response.end(request.method === "HEAD" ? undefined : body);
});

server.listen(0, "127.0.0.1", () => {
  // Written whole, then renamed, so that a reader never sees it half-written.
  fs.writeFileSync(`${portFile}.tmp`, String(server.address().port));
  fs.renameSync(`${portFile}.tmp`, portFile);
});
