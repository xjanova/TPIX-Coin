/**
 * TPIX Master Node — Shared RPC Client
 * Centralised JSON-RPC helper used by WalletManager, TransactionManager,
 * NodeManager and the explorer IPC handlers.
 * Includes rate limiting, circuit breaker and endpoint failover.
 * Developed by Xman Studio
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *  สองเรื่องที่ต้องรู้ก่อนแก้ไฟล์นี้
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  1. **User-Agent ห้ามหาย**
 *     `https://rpc.tpix.online` อยู่หลัง Cloudflare ที่เปิด bot rule ไว้
 *     คำขอที่ **ไม่มี** User-Agent หรือใช้ UA แบบ `curl/*` `Go-http-client/*`
 *     จะได้ **HTTP 403 เป็น HTML** กลับมา แล้ว JSON.parse พัง
 *     → แอปขึ้นว่า "ติดต่อเชนไม่ได้" ทั้งที่เชนปกติดี (โน้ต 2026-06-19)
 *
 *     Node `https.request` **ไม่ส่ง User-Agent เลยโดยค่าเริ่มต้น** ต่างจาก
 *     Dart/Flutter ที่ส่ง `Dart/x.y (dart:io)` (ตัวนั้นผ่าน) — บั๊กนี้จึงโผล่
 *     เฉพาะฝั่ง Electron
 *
 *     ยืนยันซ้ำ 2026-08-11:
 *       rpc.tpix.online  ไม่มี UA → 403 · curl UA → 403 · Go UA → 403 · เบราว์เซอร์ → 200
 *       rpc1.tpix.online ทุก UA → 200 (ไม่มี bot rule)
 *
 *  2. **ปลายทางเริ่มต้นคือ rpc1 ไม่ใช่ rpc**
 *     หลัง regenesis 6 ส.ค. 2026 เชนย้ายไปเครื่อง 123.253.62.252
 *     `rpc1.tpix.online` = ทางเข้าเชนใหม่ที่ไม่มี WAF ขวาง ใช้ได้กับทุก client
 *     `rpc.tpix.online` ชี้เชนใหม่แล้วเหมือนกัน แต่ยังมี bot rule ครอบอยู่
 *     จึงเก็บไว้เป็น **ตัวสำรอง** ไม่ใช่ตัวหลัก
 */

const https = require('https');
const http = require('http');

/**
 * ใช้การเชื่อมต่อซ้ำ (keep-alive)
 *
 * chain-health ต้องดึงบล็อกทีละก้อน 40 ก้อน ถ้าเปิดการเชื่อมต่อใหม่ทุกครั้ง
 * จะเสียเวลาจับมือ TLS ผ่าน Cloudflare รอบละเกือบ 1 วินาที รวมแล้ว ~17 วินาที
 * ต่อการตรวจหนึ่งครั้ง ซึ่งนอกจากช้าแล้วยังทำให้ "อายุของบล็อกล่าสุด" เพี้ยน
 * จนรายงานว่าเชนสะดุดทั้งที่เชนปกติ
 */
const keepAliveOpts = { keepAlive: true, keepAliveMsecs: 15000, maxSockets: 8 };
const httpsAgent = new https.Agent(keepAliveOpts);
const httpAgent = new http.Agent(keepAliveOpts);

let APP_VERSION = '0.0.0';
try {
    APP_VERSION = require('../package.json').version || APP_VERSION;
} catch {
    // อ่านไม่ได้ก็ไม่เป็นไร — เวอร์ชันใน UA เป็นข้อมูลเสริม
}

/**
 * UA ที่แอปใช้เป็นค่าตั้งต้น — **แนะนำตัวตามจริง**
 *
 * ทดสอบกับ rpc.tpix.online 2026-08-12 (ยิงซ้ำ 3 ครั้ง ได้ 200 ทั้งสามครั้ง)
 * กฎที่นั่นบล็อกเฉพาะ UA ที่ว่างเปล่า, `curl/*`, `python-requests/*`
 * ส่วน UA ของผลิตภัณฑ์เราเอง / okhttp / Postman / Dart ผ่านหมด
 *
 * เลิกปลอมเป็น Chrome เพราะ:
 *   - ปลอมแล้วดู log ฝั่ง Cloudflare ไม่ออกว่าอันไหนคือแอปเรา อันไหนคือบอทจริง
 *   - ถ้าวันหนึ่งกฎยกระดับเป็น JS challenge สำหรับ "เบราว์เซอร์" แอปจะพังทันที
 *     เพราะไปยืนอยู่ในกลุ่มที่ถูกท้าทาย ทั้งที่ไม่มีเบราว์เซอร์ให้รัน JS
 *   - แนะนำตัวตรงๆ แล้วค่อยไปตั้งกฎ Skip ที่ Cloudflare เป็นทางที่ถูกต้องกว่า
 */
const PRODUCT_UA = `TPIX-MasterNode/${APP_VERSION} (+https://tpix.online)`;

/**
 * UA แบบเบราว์เซอร์ — เก็บไว้เป็น **ทางถอย** เท่านั้น
 * ใช้อัตโนมัติเมื่อ UA ตามจริงโดนตอบ 403 (แปลว่ากฎฝั่ง Cloudflare เข้มขึ้น)
 */
const BROWSER_UA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/**
 * ป้ายบอกว่าคำขอนี้มาจากแอปไหน — ใช้คู่กับกฎ Skip ฝั่ง Cloudflare
 *
 * **ไม่ใช่ความลับ และห้ามใช้แทนการยืนยันตัวตน** — แอปถูกแจกเป็น .exe
 * ใครแกะไฟล์ก็อ่านค่านี้ได้ (ตรงกับข้อ "APK/binary reverse engineering" ในกฎความปลอดภัย)
 * ค่านี้มีไว้ให้ Cloudflare แยกทราฟฟิกของเราออกจากบอททั่วไปอย่างตั้งใจ
 * ไม่ได้มีไว้กันคนอื่นเข้า — ด่านกันจริงคือ rate limit + allow-list เมธอดที่ nginx
 */
const CLIENT_HEADER = 'X-TPIX-Client';
const CLIENT_ID = `tpix-masternode/${APP_VERSION}`;

/** ถ้า UA ตามจริงโดนบล็อก จะสลับมาใช้ทางถอยทั้ง process */
let useBrowserUa = false;

function activeUserAgent() {
    return useBrowserUa ? BROWSER_UA : PRODUCT_UA;
}

/** ทางเข้าเชนใหม่ (regenesis 2026-08-06) — ไม่มี Cloudflare bot rule */
const TPIX_RPC = 'https://rpc1.tpix.online';

/** ตัวสำรองเรียงตามลำดับที่จะลอง */
const FALLBACK_RPC = ['https://rpc.tpix.online'];

/**
 * ค่าเริ่มต้นเก่าที่เคยถูกบันทึกลง config ของผู้ใช้ไปแล้ว
 * ใช้ตอน migrate: ถ้าเจอค่านี้แปลว่าผู้ใช้ไม่เคยตั้งเอง ให้ย้ายมาค่าใหม่ได้เลย
 */
const LEGACY_DEFAULTS = [
    'https://rpc.tpix.online',
    'https://rpc.tpix.online/',
    'http://rpc.tpix.online',
];

// ─── Active endpoint ───────────────────────────────────────────
let activeEndpoint = TPIX_RPC;

function getEndpoint() {
    return activeEndpoint;
}

/** ตั้งปลายทางที่ผู้ใช้เลือกเอง (มาจาก config.rpcUrl) */
function setEndpoint(url) {
    if (typeof url !== 'string' || !url.trim()) return activeEndpoint;
    try {
        const parsed = new URL(url.trim());
        if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return activeEndpoint;
        activeEndpoint = parsed.origin + (parsed.pathname === '/' ? '' : parsed.pathname);
    } catch {
        // URL เสีย — คงค่าเดิมไว้ ดีกว่าทำให้ทั้งแอปยิงไปที่ว่าง
    }

    return activeEndpoint;
}

/** ปลายทางทางการของเชน — ใช้ตัดสินว่าจะสลับให้อัตโนมัติได้ไหม */
const OFFICIAL = [TPIX_RPC, ...FALLBACK_RPC];

/**
 * ลำดับปลายทางที่จะลองในหนึ่งคำขอ
 *
 * สลับให้อัตโนมัติ **เฉพาะเมื่อตอนนี้ใช้ปลายทางทางการอยู่** เท่านั้น
 * ถ้าผู้ใช้ตั้งปลายทางเองไว้ (เช่นชี้โหนดในเครื่องตัวเอง) แล้วเราแอบสลับไปใช้
 * RPC สาธารณะ ผู้ใช้จะเห็นตัวเลขของเชนสาธารณะโดยนึกว่าเป็นของโหนดตัวเอง
 * — ผิดเจตนาและหลอกตา จึงปล่อยให้ล้มไปตรงๆ พร้อมข้อความว่าต่อไม่ได้
 */
function endpointCandidates() {
    if (!OFFICIAL.includes(activeEndpoint)) return [activeEndpoint];

    const list = [activeEndpoint];
    for (const url of OFFICIAL) {
        if (!list.includes(url)) list.push(url);
    }

    return list;
}

// ─── Rate Limiter ──────────────────────────────────────────────
const RATE_LIMIT = 20;          // max requests per window
const RATE_WINDOW_MS = 1000;    // 1 second window
let requestTimestamps = [];

function isRateLimited() {
    const now = Date.now();
    requestTimestamps = requestTimestamps.filter(t => now - t < RATE_WINDOW_MS);
    if (requestTimestamps.length >= RATE_LIMIT) return true;
    requestTimestamps.push(now);
    return false;
}

// ─── Circuit Breaker ───────────────────────────────────────────
const CB_THRESHOLD = 5;         // failures before opening circuit
const CB_RESET_MS = 30000;      // 30s before half-open retry
let cbFailures = 0;
let cbState = 'closed';        // closed | open | half-open
let cbOpenedAt = 0;

function checkCircuitBreaker() {
    if (cbState === 'closed') return true;
    if (cbState === 'open') {
        if (Date.now() - cbOpenedAt > CB_RESET_MS) {
            cbState = 'half-open';
            return true; // allow one request
        }
        return false;
    }
    // half-open: allow
    return true;
}

function recordSuccess() {
    cbFailures = 0;
    cbState = 'closed';
}

function recordFailure() {
    cbFailures++;
    if (cbFailures >= CB_THRESHOLD) {
        cbState = 'open';
        cbOpenedAt = Date.now();
    }
}

function getBreakerState() {
    return { state: cbState, failures: cbFailures, endpoint: activeEndpoint };
}

// ─── Single request ────────────────────────────────────────────

/**
 * ยิงคำขอเดียวไปยัง URL ที่ระบุ — ไม่มี failover ไม่แตะ circuit breaker
 *
 * error ที่โยนออกมาจะติดธงไว้ว่าเป็นชนิดไหน:
 *   err.transport = true  → ต่อไม่ได้ / โดนบล็อกที่ขอบ / timeout  (ควรลองปลายทางอื่น)
 *   err.rpc       = true  → เชนตอบกลับมาแต่ตอบเป็น error          (ลองปลายทางอื่นก็ได้ผลเดิม)
 *
 * @param {string} url
 * @param {string} method
 * @param {Array}  params
 * @param {number} timeout — ms
 * @returns {Promise<any>}
 */
function rpcCallOn(url, method, params = [], timeout = 15000, userAgent) {
    return new Promise((resolve, reject) => {
        let target;
        try {
            target = new URL(url);
        } catch {
            const err = new Error(`RPC endpoint URL ไม่ถูกต้อง: ${url}`);
            err.transport = true;
            return reject(err);
        }

        const client = target.protocol === 'https:' ? https : http;
        const body = JSON.stringify({
            jsonrpc: '2.0',
            method,
            params,
            id: Date.now() + Math.random(),
        });

        const req = client.request(
            {
                agent: target.protocol === 'https:' ? httpsAgent : httpAgent,
                hostname: target.hostname,
                port: target.port || (target.protocol === 'https:' ? 443 : 80),
                path: target.pathname + target.search,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(body),
                    // ห้ามลบ — Cloudflare ตอบ 403 ให้คำขอที่ไม่มี UA (ดูหัวไฟล์)
                    'User-Agent': userAgent || activeUserAgent(),
                    [CLIENT_HEADER]: CLIENT_ID,
                    Accept: 'application/json, text/plain, */*',
                },
                timeout,
            },
            (res) => {
                let data = '';
                res.on('data', (c) => (data += c));
                res.on('end', () => {
                    const code = res.statusCode || 0;
                    if (code < 200 || code >= 300) {
                        const err = new Error(
                            `RPC ตอบ HTTP ${code} จาก ${target.hostname} ` +
                            `(ถูกบล็อกที่ขอบเครือข่าย หรือโหนดไม่ตอบ)`
                        );
                        err.transport = true;
                        err.statusCode = code;
                        return reject(err);
                    }

                    let json;
                    try {
                        json = JSON.parse(data);
                    } catch {
                        const err = new Error(
                            `RPC ตอบกลับไม่ใช่ JSON จาก ${target.hostname} ` +
                            `(มักแปลว่าได้หน้า HTML ของ Cloudflare มาแทน)`
                        );
                        err.transport = true;
                        return reject(err);
                    }

                    if (json.error) {
                        const err = new Error(json.error.message || 'RPC error');
                        err.rpc = true;
                        err.code = json.error.code;
                        return reject(err);
                    }

                    resolve(json.result);
                });
            },
        );

        req.on('error', (e) => {
            e.transport = true;
            reject(e);
        });
        req.on('timeout', () => {
            req.destroy();
            const err = new Error(`RPC timeout (${timeout}ms) — ${target.hostname}`);
            err.transport = true;
            reject(err);
        });
        req.write(body);
        req.end();
    });
}

// ─── ทางถอยเรื่อง User-Agent ───────────────────────────────────

/**
 * ยิงด้วย UA ตามจริงก่อน ถ้าโดน 403 ค่อยลองใหม่ด้วย UA แบบเบราว์เซอร์
 *
 * 403 จากขอบเครือข่าย = กฎ Cloudflare ไม่ชอบหน้าเรา ไม่ใช่เชนมีปัญหา
 * ลองอีกทางหนึ่งก่อนจะยอมแพ้ แล้วจำไว้ทั้ง process จะได้ไม่เสียเวลายิงสองรอบทุกครั้ง
 *
 * ที่ต้องมีเพราะบทเรียนเดิม: วันที่กฎเปลี่ยน แอปดับเงียบทั้งตัวโดยไม่มีใครรู้ว่าเพราะอะไร
 * คราวนี้อย่างน้อยมันจะพยายามต่อเอง แล้วทิ้งร่องรอยไว้ใน log ว่าเกิดอะไรขึ้น
 */
async function attemptWithUaFallback(url, method, params, timeout) {
    try {
        return await rpcCallOn(url, method, params, timeout);
    } catch (err) {
        if (err.statusCode !== 403 || useBrowserUa) throw err;

        const result = await rpcCallOn(url, method, params, timeout, BROWSER_UA);
        useBrowserUa = true;
        console.warn(
            `[rpc-client] ${new URL(url).hostname} ตอบ 403 ให้ UA "${PRODUCT_UA}" `
            + 'แต่ผ่านเมื่อใช้ UA แบบเบราว์เซอร์ — กฎฝั่ง Cloudflare เข้มขึ้นแล้ว '
            + 'ควรเพิ่มกฎ Skip ให้ header ' + CLIENT_HEADER + ' แทนการปลอม UA'
        );

        return result;
    }
}

// ─── RPC Call (rate limit + breaker + failover) ────────────────

/**
 * ส่ง JSON-RPC ไปยังเชน TPIX
 * ถ้าปลายทางปัจจุบันต่อไม่ได้ จะเลื่อนไปลองตัวสำรองแล้ว "ย้ายบ้าน" ไปใช้ตัวที่ตอบได้
 *
 * @param {string} method  — เช่น 'eth_getBalance'
 * @param {Array}  params
 * @param {number} [timeout=15000] — ms ต่อหนึ่งปลายทาง
 * @returns {Promise<any>}
 */
async function rpcCall(method, params = [], timeout = 15000) {
    if (isRateLimited()) {
        throw new Error('RPC rate limit exceeded, try again shortly');
    }

    if (!checkCircuitBreaker()) {
        throw new Error('RPC circuit breaker open — service temporarily unavailable');
    }

    const candidates = endpointCandidates();
    let lastErr;

    for (const url of candidates) {
        try {
            const result = await attemptWithUaFallback(url, method, params, timeout);
            if (url !== activeEndpoint) activeEndpoint = url; // ย้ายไปตัวที่ตอบได้
            recordSuccess();

            return result;
        } catch (err) {
            lastErr = err;
            // เชนตอบแล้วแต่ตอบเป็น error → ปลายทางอื่นก็ตอบเหมือนกัน ไม่ต้องลองต่อ
            if (err.rpc) {
                recordSuccess(); // ต่อติด แปลว่าเส้นทางยังดี
                throw err;
            }
        }
    }

    recordFailure();
    throw lastErr || new Error('RPC unreachable');
}

module.exports = {
    rpcCall,
    rpcCallOn,
    getEndpoint,
    setEndpoint,
    getBreakerState,
    endpointCandidates, // ส่งออกไว้ให้เทสต์ยืนยันนโยบายการสลับปลายทางได้ตรงๆ
    TPIX_RPC,
    FALLBACK_RPC,
    LEGACY_DEFAULTS,
    BROWSER_UA,
    PRODUCT_UA,
    CLIENT_HEADER,
    CLIENT_ID,
    activeUserAgent,
};
