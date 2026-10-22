/**
 * tpix-node-peers — ทดสอบด้วย docker ปลอม + เซิร์ฟเวอร์ HTTP ในเครื่อง (curl ตัวจริง)
 *
 *   node --test infrastructure/single-host/bootnode/
 *
 * กติกาที่ต้องจริงเสมอ: ถามไม่ได้ = ไม่ส่งอะไร (เว็บจะไม่ลดใคร) · ส่งรายการว่างเฉพาะตอน bootnode
 * ตอบมาจริงว่าไม่มีใครต่อ · token ไม่อยู่ใน argv
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');

const SCRIPT = path.join(__dirname, 'tpix-node-peers');
const PEER_A = '16Uiu2HAmLhLvBoYaoZfaMUKuibM6ac163GwKY74c5kiSLg5KvLpY';
const PEER_B = '16Uiu2HAm5SczivB6BNkSBw9svc1ejopedyTYvoT6Brw9QkDudayt';

function fakeDocker(dir, { running = 'true', peersOutput, peersExit = 0 }) {
    const out = path.join(dir, 'peers.txt');
    fs.writeFileSync(out, peersOutput);
    const file = path.join(dir, 'docker');
    fs.writeFileSync(file, [
        '#!/bin/bash',
        'if [ "$1" = "inspect" ]; then echo "' + running + '"; exit 0; fi',
        'if [ "$1" = "exec" ]; then cat "' + out.replace(/\\/g, '/') + '"; exit ' + peersExit + '; fi',
        'exit 1',
    ].join('\n'));
    fs.chmodSync(file, 0o755);

    return file.replace(/\\/g, '/');
}

async function run(opts) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'node-peers-'));
    const requests = [];
    const server = http.createServer((req, res) => {
        let body = '';
        req.on('data', (c) => { body += c; });
        req.on('end', () => {
            requests.push({ headers: req.headers, body });
            res.writeHead(opts.status || 200, { 'Content-Type': 'application/json' });
            res.end('{"ok":true}');
        });
    });
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    const env = {
        ...process.env,
        TPIX_NODE_PEERS_ENV: path.join(dir, 'none.env'),
        TPIX_NODE_PEERS_URL: `http://127.0.0.1:${server.address().port}/api/infra/node-peers`,
        TPIX_NODE_PEERS_TOKEN: opts.token === undefined ? 'secret-token' : opts.token,
        TPIX_NODE_PEERS_LOG: path.join(dir, 'log.txt'),
        DOCKER: fakeDocker(dir, opts),
    };
    await new Promise((resolve) => execFile('bash', [SCRIPT.replace(/\\/g, '/')], { env }, () => resolve()));
    server.close();
    const log = fs.existsSync(env.TPIX_NODE_PEERS_LOG) ? fs.readFileSync(env.TPIX_NODE_PEERS_LOG, 'utf8') : '';

    return { requests, log };
}

test('ส่งรายชื่อ peer ที่ไม่ซ้ำ พร้อม token ทาง header และ User-Agent', async () => {
    const { requests } = await run({
        peersOutput: `\n[PEERS LIST]\nNumber of peers: 3\n\n[0]|${PEER_A}\n[1]|${PEER_B}\n[2]|${PEER_A}\n`,
    });

    assert.equal(requests.length, 1);
    assert.deepEqual(JSON.parse(requests[0].body), { source: 'tpix-bootnode', peers: [PEER_B, PEER_A].sort() });
    assert.equal(requests[0].headers.authorization, 'Bearer secret-token');
    assert.match(requests[0].headers['user-agent'], /^tpix-node-peers\//);
});

test('bootnode ตอบว่าไม่มีใครต่อ → ส่งรายการว่าง (ข้อมูลครบ ไม่ใช่ข้อมูลขาด)', async () => {
    const { requests } = await run({ peersOutput: '\n[PEERS LIST]\nNo peers found\n' });

    assert.deepEqual(JSON.parse(requests[0].body).peers, []);
});

test('bootnode ไม่รัน → ไม่ส่งอะไร', async () => {
    const { requests } = await run({ running: 'false', peersOutput: '' });

    assert.equal(requests.length, 0);
});

test('peers list ล้ม หรือคำตอบแปลก → ไม่ส่งรายการว่างแทน', async () => {
    const failed = await run({ peersOutput: 'rpc error: connection refused', peersExit: 1 });
    assert.equal(failed.requests.length, 0);
    assert.match(failed.log, /peers list failed/);

    const odd = await run({ peersOutput: 'something else entirely' });
    assert.equal(odd.requests.length, 0);
});

test('ไม่ได้ตั้ง token → ไม่ส่ง', async () => {
    const { requests, log } = await run({ token: '', peersOutput: '[PEERS LIST]\nNo peers found' });

    assert.equal(requests.length, 0);
    assert.match(log, /TOKEN not set/);
});

test('token ไม่อยู่ใน argv ของ curl', () => {
    const src = fs.readFileSync(SCRIPT, 'utf8');
    assert.ok(!/-H\s+"Authorization/.test(src), 'ต้องส่ง token ผ่านไฟล์ header (-H @file)');
    assert.match(src, /-H @"\$hdr"/);
});
