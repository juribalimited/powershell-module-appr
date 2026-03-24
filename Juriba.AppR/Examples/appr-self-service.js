#!/usr/bin/env node
/**
 * App Readiness — Self-Service Packaging Portal
 *
 * A local web server that serves the self-service HTML UI and proxies
 * API requests to the App Readiness instance (bypassing browser CORS).
 *
 * Usage:
 *   node appr-self-service.js
 *   Then open http://localhost:3000 in your browser.
 *
 * The browser talks only to localhost — all API calls are proxied
 * through this server with the x-api-key header added server-side.
 *
 * Requirements: Node.js 18+
 */

const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");
const { URL } = require("url");

const PORT = process.env.PORT || 3000;
const HTML_FILE = path.join(__dirname, "appr-self-service.html");

const server = http.createServer(async (req, res) => {
    // Serve the HTML page
    if (req.url === "/" || req.url === "/index.html") {
        res.writeHead(200, { "Content-Type": "text/html" });
        fs.createReadStream(HTML_FILE).pipe(res);
        return;
    }

    // Proxy API requests: /proxy/{instance_base64}/api/...
    // The browser sends: /proxy/aHR0cHM6Ly9kZW1vLmFwcHIuanVyaWJhLmFwcA==/api/default-settings
    const proxyMatch = req.url.match(/^\/proxy\/([^/]+)(\/.*)/);
    if (proxyMatch) {
        const instanceUrl = Buffer.from(proxyMatch[1], "base64").toString("utf8");
        const apiPath = proxyMatch[2];
        const targetUrl = instanceUrl.replace(/\/+$/, "") + apiPath;

        // Forward all headers except host/origin (add them for the target)
        const fwdHeaders = {};
        for (const [key, val] of Object.entries(req.headers)) {
            if (!["host", "origin", "referer", "connection"].includes(key)) {
                fwdHeaders[key] = val;
            }
        }

        const parsed = new URL(targetUrl);
        const transport = parsed.protocol === "https:" ? https : http;

        // Collect request body
        const chunks = [];
        req.on("data", c => chunks.push(c));
        req.on("end", () => {
            const body = chunks.length ? Buffer.concat(chunks) : null;

            const proxyReq = transport.request(parsed, {
                method: req.method,
                headers: {
                    ...fwdHeaders,
                    "host": parsed.host,
                    ...(body ? { "content-length": body.length } : {}),
                },
            }, (proxyRes) => {
                // Return response to browser with permissive CORS
                res.writeHead(proxyRes.statusCode, {
                    ...proxyRes.headers,
                    "access-control-allow-origin": "*",
                    "access-control-allow-headers": "*",
                    "access-control-allow-methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
                });
                proxyRes.pipe(res);
            });

            proxyReq.on("error", (err) => {
                res.writeHead(502, { "Content-Type": "application/json" });
                res.end(JSON.stringify({ error: err.message }));
            });

            if (body) proxyReq.write(body);
            proxyReq.end();
        });
        return;
    }

    // Handle CORS preflight
    if (req.method === "OPTIONS") {
        res.writeHead(204, {
            "access-control-allow-origin": "*",
            "access-control-allow-headers": "*",
            "access-control-allow-methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
            "access-control-max-age": "86400",
        });
        res.end();
        return;
    }

    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found");
});

server.listen(PORT, () => {
    console.log(`\n  App Readiness Self-Service Portal`);
    console.log(`  ─────────────────────────────────`);
    console.log(`  Open http://localhost:${PORT} in your browser\n`);
});
