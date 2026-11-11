// Local pairing endpoint. Only the installed app receives the proof nonce via Launch Services.
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { createInterface } from "node:readline";
import { accessSync, constants } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { MCPClient, redeemPair, serveInterview } from "./sandbox-agent.mjs";

const sites = new Map([
  ["http://localhost:5173", "http://localhost:8080/api/v1/sandbox/mcp"],
  ["https://staffengineer.ru", "https://staffengineer.ru/api/v1/sandbox/mcp"],
]);
const host = "127.0.0.1:38473";
let challenge, active, starting;
function binaryFor(agent) {
  const name = agent === "codex" ? "codex" : "claude";
  const bins = [
    dirname(process.execPath),
    join(homedir(), ".local/bin"),
    "/opt/homebrew/bin",
    "/usr/local/bin",
  ];
  const paths = bins.map((dir) => join(dir, name));
  if (agent === "codex")
    paths.push(
      "/Applications/Codex.app/Contents/Resources/codex",
      "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
    );
  for (const path of paths) {
    try {
      accessSync(path, constants.X_OK);
      return path;
    } catch {}
  }
  return name;
}

async function connect(request, code) {
  starting = request;
  try {
    const url = sites.get(request.origin);
    const binary = binaryFor(request.agent);
    const token = await redeemPair(request.agent, binary, { url, code });
    if (active) {
      active.controller.abort();
      await active.done.catch(() => {});
    }
    const controller = new AbortController();
    const done = serveInterview(new MCPClient(url, token), request.agent, {
      signal: controller.signal,
      binary,
      waitForOldLease: true,
      onReady() {
        request.phase = "connected";
        starting = undefined;
      },
    });
    active = { controller, done };
    await done;
    request.phase = "stopped";
  } catch (e) {
    request.phase = "error";
    request.error = [
      "cli_missing",
      "auth_required",
      "incompatible_cli",
      "expired_pair",
    ].includes(e.code)
      ? e.code
      : "connection";
  } finally {
    if (starting === request) starting = undefined;
  }
}

const server = createServer(async (req, res) => {
  const origin = req.headers.origin;
  if (!sites.has(origin) || req.headers.host !== host || req.url !== "/pair") {
    res.writeHead(403).end();
    return;
  }
  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Access-Control-Allow-Private-Network", "true");
  res.setHeader("Cache-Control", "no-store");
  if (req.method === "OPTIONS") {
    res
      .writeHead(204, {
        "Access-Control-Allow-Methods": "GET, POST",
        "Access-Control-Allow-Headers": "Content-Type",
      })
      .end();
    return;
  }
  const session = challenge;
  if (!session || session.origin !== origin || Date.now() > session.expires) {
    res.writeHead(404).end();
    return;
  }
  if (req.method === "GET") {
    res.setHeader("Content-Type", "application/json");
    res.end(
      JSON.stringify({
        proof: session.proof,
        phase: session.phase,
        error: session.error,
      }),
    );
    return;
  }
  if (
    req.method !== "POST" ||
    req.headers["content-type"] !== "application/json"
  ) {
    res.writeHead(415).end();
    return;
  }
  try {
    let body = "";
    for await (const chunk of req) {
      body += chunk;
      if (body.length > 512) {
        res.writeHead(413).end();
        return;
      }
    }
    const { nonce, code } = JSON.parse(body);
    if (
      session !== challenge ||
      session.phase !== "waiting" ||
      nonce !== session.nonce ||
      !/^sdpair_[A-Za-z0-9_-]{43}$/.test(code) ||
      starting
    ) {
      res.writeHead(409).end();
      return;
    }
    session.phase = "starting";
    void connect(session, code);
    res.writeHead(202).end();
  } catch {
    res.writeHead(400).end();
  }
});
server.requestTimeout = 5000;
server.on("error", () => process.exit(1));
server.listen(38473, "127.0.0.1");
const input = createInterface({ input: process.stdin });
input.on("line", (line) => {
  if (starting || line.length > 256) return;
  try {
    const { origin, nonce, agent } = JSON.parse(line);
    if (
      !sites.has(origin) ||
      !["codex", "claude-code"].includes(agent) ||
      !/^[a-f0-9]{64}$/.test(nonce)
    )
      return;
    challenge = {
      origin,
      nonce,
      agent,
      proof: createHash("sha256").update(nonce).digest("hex"),
      expires: Date.now() + 120000,
      phase: "waiting",
    };
  } catch {}
});
input.on("close", () => {
  active?.controller.abort();
  server.closeAllConnections();
  server.close();
  if (!active) process.exit(0);
  active.done.catch(() => {}).finally(() => process.exit(0));
});
