#!/usr/bin/env python3
"""
genesis-verify.py — ตรวจ genesis.json ของ polygon-edge ก่อนเอาไปใช้จริง

เกิดขึ้นเพราะ: regenesis ล้มเหลว 8 ครั้ง (2026-05-04 → 2026-05-07) โดยไม่มี error ใดๆ
สาเหตุจริง = genesis ที่สร้างออกมามี IBFT validator set "ว่างเปล่า" ใน extraData
  extraData = 0x<vanity 32 bytes> + RLP([Validators, ProposerSeal, CommittedSeals, ...])
  ตัวที่พัง : ...c7 c0 80 c28080 c0 80   → Validators = c0 = list ว่าง  (ยาว 82 ตัวอักษร)
  ตัวที่ดี  : Validators = list ของ [address 20B, blsPubKey 48B] × 4  (ยาว ~666 ตัวอักษร)
polygon-edge ไม่ error เมื่อ --ibft-validators-prefix-path หา key ไม่เจอ — มันสร้าง genesis
ที่ validator ว่างให้เฉยๆ แล้ว engine จะ log "validator key: addr=..." ครั้งเดียวแล้วเงียบตลอดไป
peers ยังต่อกันได้ปกติ (คนละชั้นกับ consensus) → หลงทางง่ายมาก

สคริปต์นี้คือ "ประตูกัน" ห้ามข้าม: build-genesis.sh จะเรียกตัวนี้และหยุดทันทีถ้าไม่ผ่าน

ใช้:
  python3 genesis-verify.py genesis.json --validators 4 --chain-id 4289 \
      --total-supply 7000000000 [--expect-alloc alloc.env] [--json]

exit 0 = ผ่านทุกข้อ, exit 1 = มีข้อที่ FAIL (ห้าม deploy)
"""

import argparse
import json
import re
import sys

# คอนโซล Windows ภาษาไทยเป็น cp874 พิมพ์ยูนิโค้ดบางตัวไม่ได้ — บังคับ UTF-8 ไว้ก่อน
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

WEI = 10 ** 18


# ─────────────────────────── RLP decoder (พอสำหรับ extraData) ───────────────────────────
def rlp_decode(b: bytes, i: int = 0):
    """คืน (item, next_index). item เป็น bytes หรือ list ซ้อน"""
    if i >= len(b):
        raise ValueError("RLP: อ่านเกินท้าย buffer")
    p = b[i]
    if p < 0x80:
        return b[i:i + 1], i + 1
    if p <= 0xB7:
        ln = p - 0x80
        return b[i + 1:i + 1 + ln], i + 1 + ln
    if p <= 0xBF:
        lol = p - 0xB7
        ln = int.from_bytes(b[i + 1:i + 1 + lol], "big")
        s = i + 1 + lol
        return b[s:s + ln], s + ln
    # list
    if p <= 0xF7:
        ln = p - 0xC0
        s = i + 1
    else:
        lol = p - 0xF7
        ln = int.from_bytes(b[i + 1:i + 1 + lol], "big")
        s = i + 1 + lol
    end = s + ln
    items = []
    while s < end:
        item, s = rlp_decode(b, s)
        items.append(item)
    if s != end:
        raise ValueError("RLP: ความยาว list ไม่ตรง")
    return items, end


def parse_extra_data(extra_hex: str):
    """แกะ extraData → (vanity, validators) โดย validators = list ของ dict"""
    h = extra_hex[2:] if extra_hex.startswith("0x") else extra_hex
    raw = bytes.fromhex(h)
    if len(raw) < 32:
        raise ValueError(f"extraData สั้นเกินไป ({len(raw)} bytes) — ต้องมี vanity 32 bytes เป็นอย่างน้อย")
    vanity, rest = raw[:32], raw[32:]
    if not rest:
        raise ValueError("extraData มีแต่ vanity ไม่มีส่วน IstanbulExtra เลย")
    extra, _ = rlp_decode(rest)
    if not isinstance(extra, list) or not extra:
        raise ValueError("IstanbulExtra ไม่ใช่ RLP list")

    vals = []
    for v in extra[0]:
        if isinstance(v, list):          # BLS: [address(20), blsPubKey(48)]
            addr = v[0] if len(v) > 0 else b""
            bls = v[1] if len(v) > 1 else b""
            vals.append({"address": "0x" + addr.hex(), "bls_len": len(bls), "type": "bls"})
        else:                            # ECDSA: address(20) เดี่ยวๆ
            vals.append({"address": "0x" + v.hex(), "bls_len": 0, "type": "ecdsa"})
    return vanity, vals


# ─────────────────────────── ตัวช่วยรายงานผล ───────────────────────────
class Report:
    def __init__(self):
        self.rows = []
        self.failed = 0

    def check(self, ok, name, detail=""):
        self.rows.append({"ok": bool(ok), "name": name, "detail": str(detail)})
        if not ok:
            self.failed += 1
        return bool(ok)

    def emit_text(self):
        for r in self.rows:
            mark = "  OK  " if r["ok"] else " FAIL "
            line = f"[{mark}] {r['name']}"
            if r["detail"]:
                line += f"\n           {r['detail']}"
            print(line)
        print("─" * 70)
        if self.failed:
            print(f"ผลรวม: FAIL {self.failed} ข้อ จาก {len(self.rows)} ข้อ — ห้ามนำ genesis นี้ไปใช้")
        else:
            print(f"ผลรวม: ผ่านครบ {len(self.rows)} ข้อ — genesis พร้อมใช้")


def load_expected_alloc(path):
    """อ่าน alloc.env → {address_lower: amount_tpix(int)} (ข้าม comment / บรรทัดว่าง)"""
    out = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line or "=" not in line:
                continue
            _, value = line.split("=", 1)
            value = value.strip().strip('"').strip("'")
            if ":" not in value:
                continue
            addr, amount = value.split(":", 1)
            addr = addr.strip()
            if not re.fullmatch(r"0x[0-9a-fA-F]{40}", addr):
                continue
            out[addr.lower()] = int(amount.strip())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("genesis")
    ap.add_argument("--validators", type=int, default=4, help="จำนวน validator ที่คาดหวัง")
    ap.add_argument("--chain-id", type=int, default=4289)
    ap.add_argument("--total-supply", type=int, default=7_000_000_000, help="หน่วย TPIX (ไม่ใช่ wei)")
    ap.add_argument("--validator-type", default="bls", choices=["bls", "ecdsa"])
    ap.add_argument("--expect-alloc", help="ไฟล์ alloc.env สำหรับเทียบยอดรายกระเป๋า")
    ap.add_argument("--require-public-bootnodes", action="store_true",
                    help="บังคับว่า bootnode ต้องเป็น IP สาธารณะจริง (ใช้ตอน deploy ข้ามเครื่อง)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    with open(args.genesis, "r", encoding="utf-8") as fh:
        g = json.load(fh)

    rep = Report()
    gen = g.get("genesis", {})
    params = g.get("params", {})

    # ── 1. validator set ใน extraData (ข้อที่ทำให้พัง 8 ครั้ง) ──────────────────
    try:
        _, vals = parse_extra_data(gen.get("extraData", ""))
        rep.check(
            len(vals) == args.validators,
            f"extraData มี validator ครบ {args.validators} ตัว",
            f"พบ {len(vals)} ตัว | extraData ยาว {len(gen.get('extraData',''))} ตัวอักษร"
            + ("  ← ว่างเปล่า = อาการเดิมที่ค้างบล็อก 0" if len(vals) == 0 else ""),
        )
        for idx, v in enumerate(vals, 1):
            addr_ok = re.fullmatch(r"0x[0-9a-f]{40}", v["address"]) is not None
            rep.check(addr_ok, f"validator #{idx} address ถูกรูปแบบ", v["address"])
            if args.validator_type == "bls":
                rep.check(v["bls_len"] == 48,
                          f"validator #{idx} มี BLS public key 48 bytes",
                          f"พบ {v['bls_len']} bytes (type={v['type']})")
        addrs = [v["address"] for v in vals]
        rep.check(len(set(addrs)) == len(addrs), "validator ไม่ซ้ำกัน", ", ".join(addrs))
    except Exception as exc:                                   # noqa: BLE001
        rep.check(False, "แกะ extraData ได้", f"{type(exc).__name__}: {exc}")
        vals = []

    # ── 2. engine / chain params ──────────────────────────────────────────────
    ibft = params.get("engine", {}).get("ibft", {})
    rep.check(bool(ibft), "params.engine.ibft มีอยู่", json.dumps(ibft))
    rep.check(ibft.get("validator_type") == args.validator_type,
              f"validator_type = {args.validator_type}", ibft.get("validator_type"))
    bt = ibft.get("blockTime")
    rep.check(isinstance(bt, int) and 1_000_000_000 <= bt <= 30_000_000_000,
              "blockTime อยู่ในช่วง 1–30 วินาที (หน่วย ns)",
              f"{bt} ns = {bt/1e9 if isinstance(bt, int) else '?'} s")
    rep.check(params.get("chainID") == args.chain_id,
              f"chainID = {args.chain_id}", params.get("chainID"))
    rep.check(isinstance(ibft.get("epochSize"), int) and ibft["epochSize"] > 0,
              "epochSize > 0", ibft.get("epochSize"))

    # ── 3. bootnodes ──────────────────────────────────────────────────────────
    boots = g.get("bootnodes") or []
    rep.check(len(boots) >= 1, "มี bootnodes อย่างน้อย 1 รายการ", f"พบ {len(boots)}")
    ip4_re = re.compile(r"^/ip4/(\d{1,3}(?:\.\d{1,3}){3})/tcp/(\d+)/p2p/(\w+)$")
    dns_re = re.compile(r"^/dns4/([A-Za-z0-9._-]+)/tcp/(\d+)/p2p/(\w+)$")
    for b in boots:
        m4, md = ip4_re.match(b), dns_re.match(b)
        rep.check(
            bool(m4 or md),
            "bootnode multiaddr ถูกรูปแบบ",
            b + ("   ← /ip4/ ต้องตามด้วยเลข IP เท่านั้น ถ้าเป็นชื่อโฮสต์ให้ใช้ /dns4/"
                 if (not m4 and not md) else ""),
        )
        if args.require_public_bootnodes:
            rep.check(bool(m4), "bootnode เป็น IP สาธารณะ (ไม่ใช่ชื่อ container)", b)
            if m4:
                first = int(m4.group(1).split(".")[0])
                octets = m4.group(1).split(".")
                private = (
                    first == 10
                    or (first == 172 and 16 <= int(octets[1]) <= 31)
                    or (first == 192 and int(octets[1]) == 168)
                    or first == 127
                )
                rep.check(not private, "bootnode IP ไม่ใช่วง private/loopback", m4.group(1))

    # ── 4. ยอดเหรียญรวม + รายกระเป๋า ─────────────────────────────────────────
    alloc = gen.get("alloc", {}) or {}
    total_wei = 0
    for addr, entry in alloc.items():
        bal = entry.get("balance", "0x0")
        total_wei += int(bal, 16) if isinstance(bal, str) and bal.startswith("0x") else int(bal)
    total_tpix = total_wei / WEI
    rep.check(
        abs(total_tpix - args.total_supply) < 1,
        f"ยอดรวม premine = {args.total_supply:,} TPIX",
        f"พบ {total_tpix:,.4f} TPIX จาก {len(alloc)} กระเป๋า",
    )

    if args.expect_alloc:
        expected = load_expected_alloc(args.expect_alloc)
        got = {}
        for addr, entry in alloc.items():
            bal = entry.get("balance", "0x0")
            wei = int(bal, 16) if isinstance(bal, str) and bal.startswith("0x") else int(bal)
            got[addr.lower()] = wei // WEI
        for addr, amount in expected.items():
            rep.check(got.get(addr) == amount,
                      f"กระเป๋า {addr[:10]}… ได้ {amount:,} TPIX",
                      f"ในไฟล์ genesis = {got.get(addr, 'ไม่พบกระเป๋านี้')}")
        # เตือนถ้ามีกระเป๋าที่ไม่ได้อยู่ในรายการคาดหวัง และไม่ใช่ validator
        val_addrs = {v["address"].lower() for v in vals}
        extras = [a for a in got if a not in expected and a not in val_addrs]
        rep.check(not extras,
                  "ไม่มีกระเป๋าแปลกปลอมนอกเหนือจาก alloc.env + validator",
                  ", ".join(extras) if extras else "—")

    # ── 5. ข้อควรระวังอื่น ────────────────────────────────────────────────────
    rep.check(gen.get("number") in ("0x0", 0, "0x00"), "genesis block number = 0", gen.get("number"))
    gl = gen.get("gasLimit", "0x0")
    gl_int = int(gl, 16) if isinstance(gl, str) else int(gl)
    rep.check(gl_int >= 5_000_000, "gasLimit ไม่ต่ำกว่า 5,000,000", f"{gl_int:,}")

    if args.json:
        print(json.dumps({"failed": rep.failed, "checks": rep.rows}, ensure_ascii=False, indent=2))
    else:
        print(f"\n=== ตรวจ genesis: {args.genesis} ===")
        rep.emit_text()

    return 1 if rep.failed else 0


if __name__ == "__main__":
    sys.exit(main())
