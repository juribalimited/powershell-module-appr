/**
 * Juriba App Readiness — Upload, Create & Watch
 *
 * Uploads an installer to App Readiness, creates an application, and polls
 * until packaging completes (or fails). Designed as a single-file Node.js
 * script with no external dependencies — uses only built-in modules.
 *
 * SECURITY: The API key should NOT be hardcoded in this file. Use one of:
 *
 *   1. Environment variable (recommended):
 *        set APPR_API_KEY=your-key-here
 *        node appr-upload-and-watch.js
 *
 *   2. .env file (add .env to .gitignore!):
 *        Create a file called ".env" next to this script containing:
 *          APPR_API_KEY=your-key-here
 *        Then load it before running, or use a dotenv library.
 *
 *   3. Credential manager / keychain via a secrets library.
 *
 * Usage:
 *   1. Set the APPR_API_KEY environment variable.
 *   2. Optionally change INSTANCE_URL and SETUP_FILE_PATH below.
 *   3. Run:  node appr-upload-and-watch.js
 *
 * Requirements: Node.js 18+ (for native fetch and fs/promises)
 */

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION
// ─────────────────────────────────────────────────────────────────────────────

const API_KEY         = process.env.APPR_API_KEY || "";
const INSTANCE_URL    = process.env.APPR_INSTANCE || "https://demo.appr.juriba.app";
const SETUP_FILE_PATH = process.argv[2] || String.raw`C:\Packages\TeamViewer_Setup_x64.exe`;

const POLL_INTERVAL_SECONDS = 60;       // how often to check status
const POLL_TIMEOUT_MINUTES  = 60;       // give up after this long
const CHUNK_SIZE_BYTES      = 2 * 1024 * 1024; // 2 MB per upload chunk

// ─────────────────────────────────────────────────────────────────────────────
// MAIN WORKFLOW — reads top-to-bottom like a recipe
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
    log("Juriba App Readiness — Upload & Watch");
    log("──────────────────────────────────────");

    // Fail early if no API key was provided
    if (!API_KEY) {
        throw new Error(
            "No API key provided. Set the APPR_API_KEY environment variable:\n" +
            "  set APPR_API_KEY=your-key-here   (Windows cmd)\n" +
            "  $env:APPR_API_KEY='your-key'     (PowerShell)\n" +
            "  export APPR_API_KEY=your-key      (Linux/macOS)"
        );
    }

    // 1. Validate the API key works
    log("\n① Validating connection...");
    await validateConnection();
    log("  ✓ Connected to " + INSTANCE_URL);

    // 2. Read default settings (VM groups, output format bitmask)
    log("\n② Reading default settings...");
    const defaults = await getDefaultSettings();
    log(`  ✓ VM Group: ${defaults.vmGroupId}, Test Group: ${defaults.vmGroupForTestingId}, Output Bitmask: ${defaults.outputBitmask}`);

    // 3. Resolve current user ID (required by upload endpoint)
    log("\n③ Resolving user identity...");
    const userId = await resolveUserId();
    log(`  ✓ User ID: ${userId}`);

    // 4. Upload the setup file in chunks
    log(`\n④ Uploading ${SETUP_FILE_PATH}...`);
    const upload = await uploadSetupFile(SETUP_FILE_PATH, userId);
    log(`  ✓ Uploaded: ${upload.fileName} (${(upload.fileSize / 1048576).toFixed(2)} MB)`);
    log(`  ✓ UUID: ${upload.uuid}`);

    // 5. Extract metadata and get install command suggestion
    log("\n⑤ Extracting metadata & getting install command...");
    const metadata = await extractMetadata(upload.uuid);
    log(`  ✓ Name: ${metadata.name}, Manufacturer: ${metadata.manufacturer}, Version: ${metadata.version}`);
    const { installCmd } = await getCommandSuggestion(upload, metadata);
    if (installCmd) {
        log(`  ✓ Install command: ${installCmd}`);
    } else {
        log("  ⚠ No command suggestion available — packaging may fail");
    }

    // 6. Create the application
    log("\n⑥ Creating application...");
    const createResult = await createApplication({ upload, metadata, defaults, installCmd });
    log("  ✓ Application submitted");

    // 8. Wait for creation to resolve and give us an app ID
    log("\n⑧ Waiting for application ID...");
    const appId = await waitForApplicationId(upload.uuid);
    log(`  ✓ Application ID: ${appId}`);

    // 9. Poll until packaging completes or fails
    log(`\n⑨ Watching packaging status (every ${POLL_INTERVAL_SECONDS}s, timeout ${POLL_TIMEOUT_MINUTES}m)...`);
    const result = await watchStatus(appId);

    // 10. Report the outcome
    log("\n──────────────────────────────────────");
    if (result.success) {
        log(`✓ COMPLETE: ${result.status} (${result.progress}%) after ${result.elapsed}`);
    } else {
        log(`✗ FAILED: ${result.status} (${result.progress}%) after ${result.elapsed}`);
        if (result.failureReason) {
            log(`  Reason: ${result.failureReason}`);
        }
    }
    log("──────────────────────────────────────");

    return result;
}


// ─────────────────────────────────────────────────────────────────────────────
// HELPER FUNCTIONS — all the API plumbing lives below
// ─────────────────────────────────────────────────────────────────────────────

const fs   = require("fs");
const path = require("path");
const { randomUUID } = require("crypto");


// ── HTTP helpers ─────────────────────────────────────────────────────────────

/**
 * Makes a JSON API call to the App Readiness instance.
 * Handles authentication, JSON serialization, and error detection.
 * Returns the parsed response body (or null for empty responses).
 */
async function api(method, endpoint, body = null) {
    const url = `${INSTANCE_URL.replace(/\/+$/, "")}/${endpoint.replace(/^\/+/, "")}`;

    const headers = {
        "x-api-key": API_KEY,
        "Accept":    "application/json",
    };

    const options = { method, headers };

    // Always set Content-Type for non-GET requests (server returns 415 without it)
    if (body !== null) {
        headers["Content-Type"] = "application/json";
        options.body = JSON.stringify(body);
    } else if (method !== "GET") {
        headers["Content-Type"] = "application/json";
    }

    const response = await fetch(url, options);
    const contentType = response.headers.get("content-type") || "";
    const text = await response.text();

    // The SPA fallback returns 200 with HTML for invalid routes or bad auth
    if (contentType.includes("text/html")) {
        throw new Error(`Server returned HTML instead of JSON (possible auth failure). URL: ${url}`);
    }

    if (!response.ok) {
        let detail = text;
        try { detail = JSON.parse(text).message || JSON.parse(text).title || text; } catch {}
        throw new Error(`HTTP ${response.status} ${response.statusText}: ${detail}`);
    }

    if (!text || text.trim() === "") return null;
    return JSON.parse(text);
}


// ── Step 1: Validate connection ──────────────────────────────────────────────

/**
 * Validates the API key by calling an endpoint that supports x-api-key auth.
 */
async function validateConnection() {
    await api("GET", "api/packaging/upload/packageTypesMatrix");
}


// ── Step 3: Resolve user ID ─────────────────────────────────────────────────

/**
 * Gets the current user's numeric ID from the whoAmI endpoint.
 * The upload endpoint requires userId in the form data to attribute
 * the upload to the correct user.
 */
async function resolveUserId() {
    try {
        const result = await api("GET", "api/apm/user/whoAmI");
        if (result !== null && result !== undefined) return String(result);
    } catch (err) {
        log(`  ⚠ Could not resolve user ID: ${err.message}. Using 0.`);
    }
    return "0";
}


// ── Step 2: Default settings ─────────────────────────────────────────────────

/**
 * Reads the instance's Default Settings to determine:
 *   - vmGroupId           (setting type 11) — which VMs to use for repackaging
 *   - vmGroupForTestingId (setting type 12) — which VMs for smoke testing
 *   - outputBitmask       — which output formats to produce
 *
 * Output format bitmask values:
 *   MSI=1, AppV=2, MSIX=4, MSIXAppAttach=8, IntuneWin=32, PSADT=128
 */
async function getDefaultSettings() {
    const raw = await api("GET", "api/default-settings");

    const formatBits = { 1: 1, 2: 2, 3: 4, 4: 8, 5: 32, 6: 128 };
    let vmGroupId = 0, vmGroupForTestingId = 0, outputBitmask = 0;

    for (const setting of raw) {
        const type = setting.defaultSettingType;
        const val  = setting.value;

        if (type === 11) vmGroupId = parseInt(val, 10);
        else if (type === 12) vmGroupForTestingId = parseInt(val, 10);
        else if (formatBits[type] !== undefined && val === "true") {
            outputBitmask |= formatBits[type];
        }
    }

    if (outputBitmask === 0) {
        log("  ⚠ WARNING: No output formats enabled in Default Settings. Packaging may fail.");
    }

    return { vmGroupId, vmGroupForTestingId, outputBitmask };
}


// ── Step 3: Upload setup file ────────────────────────────────────────────────

/**
 * Uploads a file using Dropzone.js-style chunked uploads.
 *
 * Flow:
 *   1. Split the file into 2 MB chunks
 *   2. POST each chunk as multipart/form-data to /api/uploadChunk
 *   3. PUT a combine request to /api/v2/uploadChunk/async
 *
 * Returns { uuid, fileName, fileSize, totalChunks }.
 */
async function uploadSetupFile(filePath, userId = "0") {
    const stat     = fs.statSync(filePath);
    const fileName = path.basename(filePath);
    const fileSize = stat.size;
    const uuid     = randomUUID();
    const totalChunks = Math.ceil(fileSize / CHUNK_SIZE_BYTES);

    log(`  Uploading '${fileName}' (${(fileSize / 1048576).toFixed(2)} MB) in ${totalChunks} chunk(s)`);

    // Upload each chunk
    const fd = fs.openSync(filePath, "r");
    try {
        for (let i = 0; i < totalChunks; i++) {
            const offset    = i * CHUNK_SIZE_BYTES;
            const remaining = fileSize - offset;
            const chunkSize = Math.min(CHUNK_SIZE_BYTES, remaining);
            const buffer    = Buffer.alloc(chunkSize);

            fs.readSync(fd, buffer, 0, chunkSize, offset);

            await uploadChunk({
                uuid, fileName, fileSize, chunkSize, totalChunks,
                chunkIndex: i, chunkByteOffset: offset, buffer, userId,
            });

            log(`  Chunk ${i + 1}/${totalChunks} uploaded`);
        }
    } finally {
        fs.closeSync(fd);
    }

    // Combine chunks on the server
    await combineChunks({ uuid, fileName, fileSize, totalChunks });
    log("  Chunks combined on server");

    return { uuid, fileName, fileSize, totalChunks };
}

/**
 * Uploads a single chunk as multipart/form-data.
 * Uses the Dropzone.js field names the server expects (dzUuid, dzChunkIndex, etc.).
 *
 * Writes the chunk to a temp file (with the original filename — the server
 * validates the extension and rejects .tmp files), then uses fs.openAsBlob()
 * with native FormData for reliable binary upload handling.
 */
async function uploadChunk({ uuid, fileName, fileSize, chunkSize, totalChunks, chunkIndex, chunkByteOffset, buffer, userId = "0" }) {
    const url = `${INSTANCE_URL.replace(/\/+$/, "")}/api/uploadChunk`;
    const os = require("os");

    // Write chunk to a temp file with the original filename
    // (server validates the file extension in the Content-Disposition)
    const tmpDir = path.join(os.tmpdir(), `juriba-${uuid}`);
    if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
    const tmpPath = path.join(tmpDir, fileName);

    try {
        fs.writeFileSync(tmpPath, buffer);

        // Create a proper Blob from the file on disk
        const fileBlob = await fs.promises.readFile(tmpPath)
            .then(data => new Blob([data], { type: "application/octet-stream" }));

        const form = new FormData();
        form.append("dzUuid",             uuid);
        form.append("dzChunkIndex",       String(chunkIndex));
        form.append("dzTotalFileSize",    String(fileSize));
        form.append("dzCurrentChunkSize", String(chunkSize));
        form.append("dzTotalChunkCount",  String(totalChunks));
        form.append("dzChunkByteOffset",  String(chunkByteOffset));
        form.append("dzChunkSize",        String(CHUNK_SIZE_BYTES));
        form.append("dzFilename",         fileName);
        form.append("userId",             userId);
        form.append("file",               fileBlob, fileName);

        const response = await fetch(url, {
            method: "POST",
            headers: {
                "x-api-key":     API_KEY,
                "Authorization": `Bearer ${API_KEY}`,
                "Accept":        "application/json",
                // Do NOT set Content-Type — let FormData set boundary automatically
            },
            body: form,
        });

        if (!response.ok) {
            const text = await response.text();
            throw new Error(`Chunk upload failed: HTTP ${response.status} — ${text}`);
        }
    } finally {
        try { fs.unlinkSync(tmpPath); } catch {}
        try { fs.rmdirSync(tmpDir); } catch {}
    }
}

/**
 * Tells the server to combine all uploaded chunks into the final file.
 */
async function combineChunks({ uuid, fileName, fileSize, totalChunks }) {
    const url = `${INSTANCE_URL.replace(/\/+$/, "")}/api/v2/uploadChunk/async`;

    const response = await fetch(url, {
        method: "PUT",
        headers: {
            "x-api-key":    API_KEY,
            "Accept":       "application/json",
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            dzIdentifier:  uuid,
            fileName:      fileName,
            expectedBytes: fileSize,
            totalChunks:   totalChunks,
            uploadType:    0,
        }),
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(`Chunk combine failed: HTTP ${response.status} — ${text}`);
    }
}


// ── Step 4: Extract metadata ─────────────────────────────────────────────────

/**
 * Extracts application metadata (name, manufacturer, version).
 *
 * Tries three sources in order:
 *   1. Server-side extraction API (PE header analysis on the server)
 *   2. Client-side PE headers via PowerShell (FileVersionInfo — Windows only)
 *   3. File name as last resort
 */
async function extractMetadata(uuid) {
    const fallback = {
        name:         path.parse(SETUP_FILE_PATH).name,
        manufacturer: "Unknown",
        version:      "1.0",
    };

    // Try server-side extraction first
    try {
        const meta = await api("PUT", `api/apm/application/setupFile/getMetadata/${uuid}`);
        if (meta && meta.applicationName) {
            return {
                name:         meta.applicationName         || fallback.name,
                manufacturer: meta.applicationManufacturer  || fallback.manufacturer,
                version:      meta.applicationVersion       || fallback.version,
            };
        }
    } catch (err) {
        log(`  Server-side extraction failed: ${err.message}`);
    }

    // Fall back to client-side PE headers via PowerShell (Windows)
    try {
        const { execSync } = require("child_process");
        const psCmd = `[System.Diagnostics.FileVersionInfo]::GetVersionInfo('${SETUP_FILE_PATH.replace(/'/g, "''")}') | Select-Object ProductName,CompanyName,ProductVersion | ConvertTo-Json -Compress`;
        const raw = execSync(`pwsh -NoProfile -Command "${psCmd}"`, { encoding: "utf8", timeout: 10000 });
        const info = JSON.parse(raw.trim());
        if (info.ProductName) {
            log(`  Using client-side PE headers (FileVersionInfo)`);
            return {
                name:         (info.ProductName    || "").trim() || fallback.name,
                manufacturer: (info.CompanyName    || "").trim() || fallback.manufacturer,
                version:      (info.ProductVersion || "").trim() || fallback.version,
            };
        }
    } catch (err) {
        log(`  Client-side PE extraction failed: ${err.message}`);
    }

    log(`  Using file name as fallback`);
    return fallback;
}


// ── Step 5: Command suggestion ──────────────────────────────────────────────

/**
 * Calls the command suggestion API to get the best install command.
 * Applies source priority: Juriba KB (3) → Programmatic (1) → AI (2).
 * Within each source, prefers previously successful commands, then highest
 * success rate, then the API's own ranking order.
 *
 * Returns { installCmd, suggestionMeta } where suggestionMeta contains
 * the app name/manufacturer/version from the KB response.
 */
async function getCommandSuggestion(upload, metadata) {
    const noResult = { installCmd: null, suggestionMeta: null };
    try {
        const result = await api("POST", "api/application/temp/commands/suggestion", {
            uid:                     upload.uuid,
            filename:                upload.fileName,
            applicationName:         metadata.name,
            applicationManufacture:  metadata.manufacturer,  // Note: API uses "Manufacture" not "Manufacturer"
            applicationVersion:      metadata.version,
            packageType:             10,
            appId:                   0,
            sendUda:                 true,
        });

        // Extract metadata from the suggestion response (KB knows the real name)
        const suggestionMeta = {
            name:         result?.applicationName         || null,
            manufacturer: result?.applicationManufacture   || null,
            version:      result?.applicationVersion       || null,
        };

        const commands = result?.commands;
        if (!commands || commands.length === 0) {
            log("  No command suggestions returned");
            return { installCmd: null, suggestionMeta };
        }

        // Filter to install commands (type=1)
        const installCmds = commands.filter(c => c.type === 1);
        log(`  ${installCmds.length} install command candidate(s):`);

        const sourceLabels = { 3: "JuribaKB", 1: "Programmatic", 2: "AI" };
        for (const c of installCmds) {
            const src = sourceLabels[c.source] || `Unknown(${c.source})`;
            log(`    [${src}] ${c.command}  (success=${c.successRate} failure=${c.failureRate} lastResult=${c.lastResult})`);
        }

        // Source priority: Juriba KB (3), Programmatic (1), AI (2)
        for (const sourcePriority of [3, 1, 2]) {
            const candidates = installCmds.filter(c => c.source === sourcePriority);
            if (candidates.length > 0) {
                candidates.sort((a, b) => {
                    const aLast = a.lastResult > 0 ? 0 : 1;
                    const bLast = b.lastResult > 0 ? 0 : 1;
                    if (aLast !== bLast) return aLast - bLast;
                    return (b.successRate || 0) - (a.successRate || 0);
                });
                const pick = candidates[0];
                const src = sourceLabels[sourcePriority];
                log(`  Selected [${src}]: ${pick.command}`);
                return { installCmd: pick.command, suggestionMeta };
            }
        }

        return { installCmd: null, suggestionMeta };
    } catch (err) {
        log(`  ⚠ Command suggestion failed: ${err.message}`);
        return noResult;
    }
}


// ── Step 6: Create application ──────────────────────────────────────────────

/**
 * Creates the application by POSTing the exact payload the UI sends.
 * Includes the install command from the command suggestion API.
 * VM groups and output format bitmask come from Default Settings.
 */
async function createApplication({ upload, metadata, defaults, installCmd }) {
    const appInfo = {
        appVer:                 metadata.version,
        manufacturer:           metadata.manufacturer,
        name:                   metadata.name,
        pkgVer:                 "1.0",
        siteCode:               "GLOBAL",
        isDiscovery:            false,
        preReqIds:              [],
        upgradeAppIds:          [],
        existingAppId:          -1,
        fullPreReqInfo:         [],
        source:                 0,
        sourceFileName:         upload.fileName,
        sendUda:                true,
        operatingSystemType:    0,
        isAutomatedRepackaging: false,
    };

    // Add install command if we have one (uninstall left blank intentionally)
    if (installCmd) {
        appInfo.cmdLine = installCmd;
    }

    const body = {
        applicationId: -1,
        applicationInfo: appInfo,
        preReqs:        [],
        fullPreReqInfo: [],
        upgradeAppIds:  [],
        setAsMainSource: true,
        uploadChunkModel: {
            dzIdentifier:  upload.uuid,
            fileName:      upload.fileName,
            expectedBytes: upload.fileSize,
            totalChunks:   upload.totalChunks,
        },
        packageTypeMatrixModel: {
            from: 0,
            to:   defaults.outputBitmask,
        },
        runImmediately:     true,
        runEvAsAnotherUser: null,
    };

    if (defaults.vmGroupId > 0)           body.vmGroupId           = defaults.vmGroupId;
    if (defaults.vmGroupForTestingId > 0) body.vmGroupForTestingId = defaults.vmGroupForTestingId;

    return await api("POST", "api/apm/application/async", body);
}


// ── Step 7: Wait for application ID ──────────────────────────────────────────

/**
 * After the async create call, the server takes a few seconds to allocate
 * the application ID. This polls the creation state endpoint until the ID
 * appears (nested inside response.data.applicationId).
 */
async function waitForApplicationId(uuid, timeoutSeconds = 300) {
    const deadline = Date.now() + timeoutSeconds * 1000;

    while (Date.now() < deadline) {
        try {
            const state = await api("GET", `api/apm/application/creation/${uuid}/state`);
            const appId = state?.data?.applicationId || state?.applicationId;
            if (appId && appId > 0) return appId;
        } catch {}

        await sleep(10_000);
    }

    throw new Error(`Timed out waiting for application ID after ${timeoutSeconds}s`);
}


// ── Step 8: Watch packaging status ───────────────────────────────────────────

/**
 * Polls the application detail endpoint for the authoritative packaging status.
 * The status lives at response.ext.status; progress at response.ext.progressPercent.
 *
 * Terminal states:
 *   Success: ReadyForQualityReview, QualityReview, ReadyForUat, ReadyForPublishing, Published
 *   Failure: Failed, FailedPackaging, FailedToPackage, Cancelled
 *
 * On failure, collects the reason from the application's event log.
 */
async function watchStatus(appId) {
    const TERMINAL_SUCCESS = new Set([
        "ReadyForQualityReview", "QualityReview", "ReadyForUat",
        "Uat", "ReadyForPublishing", "Published",
    ]);
    const TERMINAL_FAILURE = new Set([
        "Failed", "FailedPackaging", "FailedToPackage", "Cancelled",
    ]);

    const startTime = Date.now();
    const deadline  = startTime + POLL_TIMEOUT_MINUTES * 60_000;
    let pollCount   = 0;
    let prevStatus  = null;

    while (Date.now() < deadline) {
        pollCount++;
        const elapsed = formatElapsed(Date.now() - startTime);
        const now     = new Date().toLocaleTimeString("en-GB");

        let detail;
        try {
            detail = await api("GET", `api/apm/application/${appId}`);
        } catch (err) {
            log(`  [${now}] Poll #${pollCount}: Error — ${err.message}`);
            await sleep(POLL_INTERVAL_SECONDS * 1000);
            continue;
        }

        const status   = detail?.ext?.status || "Unknown";
        const progress = detail?.ext?.progressPercent ?? 0;
        const key      = `${status}|${progress}`;

        if (key !== prevStatus) {
            log(`  [${now}] Poll #${pollCount} (${elapsed}): ${status} (${progress}%)`);
            prevStatus = key;
        } else {
            log(`  [${now}] Poll #${pollCount} (${elapsed}): ${status} (${progress}%) — no change`);
        }

        // Check for terminal states
        if (TERMINAL_SUCCESS.has(status)) {
            return {
                success: true, status, progress, appId,
                elapsed, pollCount, failureReason: null,
            };
        }

        if (TERMINAL_FAILURE.has(status)) {
            const reason = await getFailureReason(appId);
            return {
                success: false, status, progress, appId,
                elapsed, pollCount, failureReason: reason,
            };
        }

        await sleep(POLL_INTERVAL_SECONDS * 1000);
    }

    // Timed out
    return {
        success: false, status: "Timeout", progress: 0, appId,
        elapsed: formatElapsed(Date.now() - startTime),
        pollCount,
        failureReason: `Timed out after ${POLL_TIMEOUT_MINUTES} minutes`,
    };
}

/**
 * When packaging fails, queries the application's event log to find
 * the most recent error event and returns its description as the
 * failure reason. Falls back to a generic message if no events are found.
 */
async function getFailureReason(appId) {
    try {
        const events = await api("GET", `api/apm/application/${appId}/events`);

        if (!events || !Array.isArray(events) || events.length === 0) {
            return "No events found — check the application logs in the UI.";
        }

        // Look for error/failure events (typically the most recent ones)
        // Events may have: description, eventType, status, message fields
        const failureEvents = events.filter(e =>
            (e.description && /fail|error|exception/i.test(e.description)) ||
            (e.message     && /fail|error|exception/i.test(e.message)) ||
            (e.eventType   && /fail|error/i.test(String(e.eventType)))
        );

        if (failureEvents.length > 0) {
            const latest = failureEvents[failureEvents.length - 1];
            return latest.description || latest.message || JSON.stringify(latest);
        }

        // No obvious failure event — return the last event as context
        const last = events[events.length - 1];
        return last.description || last.message || `Last event: ${JSON.stringify(last)}`;

    } catch (err) {
        return `Could not retrieve failure reason: ${err.message}`;
    }
}


// ── Utilities ────────────────────────────────────────────────────────────────

function log(msg) {
    console.log(msg);
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function formatElapsed(ms) {
    const totalSec = Math.floor(ms / 1000);
    const min = Math.floor(totalSec / 60);
    const sec = totalSec % 60;
    if (min === 0) return `${sec}s`;
    return `${min}m ${sec}s`;
}


// ─────────────────────────────────────────────────────────────────────────────
// RUN
// ─────────────────────────────────────────────────────────────────────────────

main().catch(err => {
    console.error("\n✗ Fatal error:", err.message);
    process.exit(1);
});
