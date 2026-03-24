#!/usr/bin/env node
/**
 * App Readiness — Self-Service Packaging Portal (proxy server)
 *
 * Serves the HTML UI and proxies API requests + KB downloads to bypass CORS.
 *
 * Usage:
 *   node appr-self-service.js
 *   Then open http://localhost:3000
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

function proxyRequest(targetUrl, req, res, bodyOverride) {
    const parsed = new URL(targetUrl);
    const transport = parsed.protocol === "https:" ? https : http;

    const fwdHeaders = {};
    for (const [key, val] of Object.entries(req.headers)) {
        if (!["host", "origin", "referer", "connection"].includes(key)) fwdHeaders[key] = val;
    }
    fwdHeaders["host"] = parsed.host;

    const chunks = [];
    const onBody = (body) => {
        const proxyReq = transport.request(parsed, {
            method: req.method,
            headers: { ...fwdHeaders, ...(body ? { "content-length": body.length } : {}) },
        }, (proxyRes) => {
            const rHeaders = { ...proxyRes.headers,
                "access-control-allow-origin": "*",
                "access-control-allow-headers": "*",
                "access-control-allow-methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
            };
            res.writeHead(proxyRes.statusCode, rHeaders);
            proxyRes.pipe(res);
        });
        proxyReq.on("error", (err) => {
            res.writeHead(502, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: err.message }));
        });
        if (body) proxyReq.write(body);
        proxyReq.end();
    };

    if (bodyOverride !== undefined) { onBody(bodyOverride); return; }
    req.on("data", c => chunks.push(c));
    req.on("end", () => onBody(chunks.length ? Buffer.concat(chunks) : null));
}

const server = http.createServer((req, res) => {
    // Serve HTML
    if (req.url === "/" || req.url === "/index.html") {
        res.writeHead(200, { "Content-Type": "text/html" });
        fs.createReadStream(HTML_FILE).pipe(res);
        return;
    }
    // Serve the testing-visibility variant
    if (req.url === "/testing" || req.url === "/testing.html") {
        const testFile = path.join(__dirname, "appr-self-service-with-testing-visibility.html");
        if (fs.existsSync(testFile)) { res.writeHead(200, { "Content-Type": "text/html" }); fs.createReadStream(testFile).pipe(res); return; }
    }

    // Health check for the HTML to detect proxy availability
    if (req.url === "/health") {
        res.writeHead(200, { "Content-Type": "application/json",
            "access-control-allow-origin": "*", "access-control-allow-headers": "*" });
        res.end('{"ok":true}');
        return;
    }

    // Download a KB file (bypass vendor CDN CORS)
    // GET /download?url=https://7-zip.org/a/7z2600-x64.exe
    if (req.url.startsWith("/download?")) {
        const dlUrl = new URL(req.url, "http://localhost").searchParams.get("url");
        if (!dlUrl) { res.writeHead(400); res.end("Missing url param"); return; }
        const parsed = new URL(dlUrl);
        const transport = parsed.protocol === "https:" ? https : http;
        transport.get(dlUrl, { headers: { "User-Agent": "JuribaAppR/1.0" } }, (dlRes) => {
            // Follow redirects
            if (dlRes.statusCode >= 300 && dlRes.statusCode < 400 && dlRes.headers.location) {
                transport.get(dlRes.headers.location, { headers: { "User-Agent": "JuribaAppR/1.0" } }, (dlRes2) => {
                    res.writeHead(200, {
                        "Content-Type": "application/octet-stream",
                        "Content-Length": dlRes2.headers["content-length"] || "",
                        "access-control-allow-origin": "*",
                    });
                    dlRes2.pipe(res);
                }).on("error", e => { res.writeHead(502); res.end(e.message); });
                return;
            }
            res.writeHead(dlRes.statusCode, {
                "Content-Type": "application/octet-stream",
                "Content-Length": dlRes.headers["content-length"] || "",
                "access-control-allow-origin": "*",
            });
            dlRes.pipe(res);
        }).on("error", e => { res.writeHead(502); res.end(e.message); });
        return;
    }

    // Extract PE metadata via PowerShell FileVersionInfo
    // POST /metadata?name=filename.exe  (raw file bytes as body, NOT multipart)
    if (req.url.startsWith("/metadata") && req.method === "POST") {
        const fileName = new URL(req.url, "http://localhost").searchParams.get("name") || "upload.exe";
        const chunks = [];
        req.on("data", c => chunks.push(c));
        req.on("end", () => {
            const body = Buffer.concat(chunks);
            const tmpDir = path.join(require("os").tmpdir(), "appr-meta-" + Date.now());
            fs.mkdirSync(tmpDir, { recursive: true });
            const tmpPath = path.join(tmpDir, fileName);
            fs.writeFileSync(tmpPath, body);

            const { execSync } = require("child_process");
            const corsHeaders = { "Content-Type": "application/json", "access-control-allow-origin": "*", "access-control-allow-headers": "*" };
            try {
                const psCmd = `[System.Diagnostics.FileVersionInfo]::GetVersionInfo('${tmpPath.replace(/'/g, "''")}') | Select-Object ProductName,CompanyName,ProductVersion | ConvertTo-Json -Compress`;
                const raw = execSync(`pwsh -NoProfile -Command "${psCmd}"`, { encoding: "utf8", timeout: 15000 });
                const info = JSON.parse(raw.trim());
                res.writeHead(200, corsHeaders);
                res.end(JSON.stringify({
                    name: (info.ProductName || "").trim() || null,
                    manufacturer: (info.CompanyName || "").trim() || null,
                    version: (info.ProductVersion || "").trim() || null,
                }));
            } catch (e) {
                res.writeHead(200, corsHeaders);
                res.end(JSON.stringify({ name: null, manufacturer: null, version: null, error: e.message }));
            } finally {
                try { fs.unlinkSync(tmpPath); } catch {}
                try { fs.rmdirSync(tmpDir); } catch {}
            }
        });
        return;
    }

    // Proxy API: /proxy/{base64_instance}/api/...
    const proxyMatch = req.url.match(/^\/proxy\/([^/]+)(\/.*)/);
    if (proxyMatch) {
        const instanceUrl = Buffer.from(proxyMatch[1], "base64").toString("utf8");
        const targetUrl = instanceUrl.replace(/\/+$/, "") + proxyMatch[2];
        proxyRequest(targetUrl, req, res);
        return;
    }

    // CORS preflight
    if (req.method === "OPTIONS") {
        res.writeHead(204, {
            "access-control-allow-origin": "*", "access-control-allow-headers": "*",
            "access-control-allow-methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
            "access-control-max-age": "86400",
        });
        res.end();
        return;
    }

    res.writeHead(404); res.end("Not found");
});

server.listen(PORT, () => {
    console.log(`\n  App Readiness Self-Service Portal`);
    console.log(`  ---------------------------------`);
    console.log(`  Open http://localhost:${PORT} in your browser\n`);
});
