#!/usr/bin/env python3
"""
validator_sign_binding.py — เซ็นการผูกกุญแจ validator ของ TPIX Chain บนเครื่องที่รันโหนด

ทำไมต้องมี
    สัญญา NodeRegistryV2 เก็บแค่ว่าใคร stake ชั้น Validator ไม่มีช่องเก็บกุญแจที่ปิดบล็อก
    เจ้าของเชนจึงต้องรู้ว่า "stake ของกระเป๋า X = ที่อยู่ IBFT Y + BLS key Z" ก่อนโหวตเข้า
    การผูกเซ็น 2 ใบ: (1) กุญแจ validator — สคริปต์นี้ บนเครื่องที่ถือกุญแจ
                     (2) กระเป๋าที่ stake — ในโปรแกรม TPIX Master Node
    กุญแจ validator ไม่ต้องออกจากเซิร์ฟเวอร์ และกุญแจกระเป๋าไม่ต้องขึ้นเซิร์ฟเวอร์

ใช้งาน (Python 3.8+ ไม่ต้องติดตั้งอะไรเพิ่ม)
    # โหนดรันใน docker (data-dir ของคอนเทนเนอร์ถูก mount ไว้ที่ /opt/tpix-node/data)
    sudo python3 validator_sign_binding.py \\
        --staking-wallet 0xกระเป๋าที่stake \\
        --data-dir /opt/tpix-node/data \\
        --edge "docker exec tpix-node polygon-edge" --edge-data-dir /data

    # มี polygon-edge ในเครื่อง
    python3 validator_sign_binding.py --staking-wallet 0x… --data-dir ./chain-data --edge polygon-edge

    ได้ JSON หนึ่งบรรทัด → คัดลอกไปวางในโปรแกรม TPIX Master Node (แท็บ Validator) ภายใน 30 นาที

ข้อความที่เซ็นต้องตรงกับ ThaiXTrade ValidatorKeyBindingService::message() ทุกตัวอักษร
ลายเซ็นเป็น personal_sign (EIP-191) แบบเดียวกับ MetaMask / ethers — deterministic (RFC 6979) + low-s

Developed by Xman Studio
"""

import argparse
import hashlib
import hmac
import json
import os
import re
import shlex
import subprocess
import sys
import time

CHAIN_ID = 4289
TITLE = "TPIX Chain validator key binding"

# ── Keccak-256 (แบบ Ethereum — ไม่ใช่ hashlib.sha3_256 ซึ่งเติมบิตต่างกัน) ─────────
_RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
_ROT = [
    [0, 36, 3, 41, 18],
    [1, 44, 10, 45, 2],
    [62, 6, 43, 15, 61],
    [28, 55, 25, 21, 56],
    [27, 20, 39, 8, 14],
]
_MASK = (1 << 64) - 1


def _rol(v, n):
    return ((v << n) | (v >> (64 - n))) & _MASK if n else v


def _keccak_f(a):
    for rc in _RC:
        c = [a[x][0] ^ a[x][1] ^ a[x][2] ^ a[x][3] ^ a[x][4] for x in range(5)]
        d = [c[(x - 1) % 5] ^ _rol(c[(x + 1) % 5], 1) for x in range(5)]
        for x in range(5):
            for y in range(5):
                a[x][y] ^= d[x]
        b = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                b[y][(2 * x + 3 * y) % 5] = _rol(a[x][y], _ROT[x][y])
        for x in range(5):
            for y in range(5):
                a[x][y] = b[x][y] ^ ((~b[(x + 1) % 5][y]) & b[(x + 2) % 5][y] & _MASK)
        a[0][0] ^= rc


def keccak256(data: bytes) -> bytes:
    rate = 136
    msg = bytearray(data) + b"\x01"
    while len(msg) % rate:
        msg.append(0)
    msg[-1] |= 0x80
    state = [[0] * 5 for _ in range(5)]
    for off in range(0, len(msg), rate):
        block = msg[off:off + rate]
        for i in range(rate // 8):
            state[i % 5][i // 5] ^= int.from_bytes(block[8 * i:8 * i + 8], "little")
        _keccak_f(state)
    return b"".join(state[i % 5][i // 5].to_bytes(8, "little") for i in range(4))


# ── secp256k1 ─────────────────────────────────────────────────────────────────
P = 2 ** 256 - 2 ** 32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    if p1[0] == p2[0] and (p1[1] + p2[1]) % P == 0:
        return None
    if p1 == p2:
        lam = 3 * p1[0] * p1[0] * pow(2 * p1[1], P - 2, P) % P
    else:
        lam = (p2[1] - p1[1]) * pow(p2[0] - p1[0], P - 2, P) % P
    x = (lam * lam - p1[0] - p2[0]) % P
    return x, (lam * (p1[0] - x) - p1[1]) % P


def _mul(k, point=G):
    result = None
    while k:
        if k & 1:
            result = _add(result, point)
        point = _add(point, point)
        k >>= 1
    return result


def address_of(priv: int) -> str:
    x, y = _mul(priv)
    return "0x" + keccak256(x.to_bytes(32, "big") + y.to_bytes(32, "big"))[-20:].hex()


def _rfc6979_k(priv: int, digest: bytes) -> int:
    x = priv.to_bytes(32, "big")
    h = (int.from_bytes(digest, "big") % N).to_bytes(32, "big")
    v, k = b"\x01" * 32, b"\x00" * 32
    k = hmac.new(k, v + b"\x00" + x + h, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    k = hmac.new(k, v + b"\x01" + x + h, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    while True:
        v = hmac.new(k, v, hashlib.sha256).digest()
        candidate = int.from_bytes(v, "big")
        if 1 <= candidate < N:
            return candidate
        k = hmac.new(k, v + b"\x00", hashlib.sha256).digest()
        v = hmac.new(k, v, hashlib.sha256).digest()


def sign_digest(priv: int, digest: bytes):
    """คืน (r, s, recovery_id) แบบ low-s เหมือน ethers / noble-secp256k1"""
    z = int.from_bytes(digest, "big")
    k = _rfc6979_k(priv, digest)
    rx, ry = _mul(k)
    r = rx % N
    s = pow(k, N - 2, N) * (z + r * priv) % N
    recid = (ry & 1) | (2 if rx >= N else 0)
    if s > N // 2:
        s = N - s
        recid ^= 1
    return r, s, recid


def personal_sign(priv: int, message: str) -> str:
    data = message.encode("utf-8")
    digest = keccak256(b"\x19Ethereum Signed Message:\n" + str(len(data)).encode() + data)
    r, s, recid = sign_digest(priv, digest)
    return "0x" + r.to_bytes(32, "big").hex() + s.to_bytes(32, "big").hex() + format(27 + recid, "02x")


# ── การผูก ────────────────────────────────────────────────────────────────────
def binding_message(chain_id, staking_wallet, validator_address, bls, node_id, signed_at) -> str:
    """ต้องตรงกับ ValidatorKeyBindingService::message() (ThaiXTrade) และ buildBindingMessage() (TPIX-Masternode)"""
    return "\n".join([
        TITLE,
        "chain_id: %d" % chain_id,
        "staking_wallet: " + staking_wallet.lower(),
        "validator_address: " + validator_address.lower(),
        "bls_public_key: " + bls.lower(),
        "node_id: " + node_id,
        "signed_at: %d" % signed_at,
    ])


def read_private_key(path: str) -> int:
    raw = open(path, "r", encoding="ascii").read().strip()
    if raw.startswith("0x"):
        raw = raw[2:]
    if not re.fullmatch(r"[0-9a-fA-F]{64}", raw):
        raise ValueError("ไฟล์กุญแจไม่ใช่ hex 64 ตัวอักษร: " + path)
    priv = int(raw, 16)
    if not 1 <= priv < N:
        raise ValueError("กุญแจอยู่นอกช่วงของ secp256k1")
    return priv


def secrets_output(edge_cmd: str, data_dir: str) -> dict:
    """polygon-edge secrets output --json → {address, bls, node_id} (ข้อมูลสาธารณะเท่านั้น)"""
    out = subprocess.run(shlex.split(edge_cmd) + ["secrets", "output", "--json", "--data-dir", data_dir],
                         capture_output=True, text=True, timeout=60, check=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("อ่านผล secrets output ไม่ได้")


def build(args) -> dict:
    if not re.fullmatch(r"0x[0-9a-fA-F]{40}", args.staking_wallet or ""):
        raise ValueError("--staking-wallet ต้องเป็นที่อยู่ 0x + 40 ตัวอักษร")

    key_file = args.key_file or os.path.join(args.data_dir, "consensus", "validator.key")
    priv = read_private_key(key_file)
    validator = address_of(priv)

    bls, node_id = args.bls, args.node_id
    if not (bls and node_id):
        if not args.edge:
            raise ValueError("ต้องใส่ --bls และ --node-id หรือ --edge ให้สคริปต์อ่านจาก polygon-edge")
        info = secrets_output(args.edge, args.edge_data_dir or args.data_dir)
        # กุญแจที่เซ็นต้องมาจาก data-dir เดียวกับ BLS — ไม่งั้นผูก BLS ของเครื่องอื่นโดยไม่รู้ตัว
        if info.get("address", "").lower() != validator:
            raise ValueError("ที่อยู่จาก secrets output (%s) ไม่ตรงกับไฟล์กุญแจ (%s) — คนละ data-dir"
                             % (info.get("address"), validator))
        bls, node_id = info["bls"], info["node_id"]

    if not re.fullmatch(r"0x[0-9a-fA-F]{96}", bls or ""):
        raise ValueError("BLS public key ต้องเป็น 0x + 96 ตัวอักษร")
    if not re.fullmatch(r"16Uiu2HA[1-9A-HJ-NP-Za-km-z]{40,60}", node_id or ""):
        raise ValueError("node ID ไม่ใช่ libp2p peer ID (ขึ้นต้น 16Uiu2HA)")
    if validator == args.staking_wallet.lower():
        raise ValueError("กุญแจ validator ต้องไม่ใช่กระเป๋าที่ stake")

    signed_at = int(args.signed_at) if args.signed_at else int(time.time())
    message = binding_message(args.chain_id, args.staking_wallet, validator, bls, node_id, signed_at)
    return {
        "tpix_validator_binding": 1,
        "chain_id": args.chain_id,
        "staking_wallet": args.staking_wallet.lower(),
        "validator_address": validator,
        "bls_public_key": bls.lower(),
        "node_id": node_id,
        "signed_at": signed_at,
        "validator_signature": personal_sign(priv, message),
    }


def main(argv=None):
    p = argparse.ArgumentParser(description="เซ็นการผูกกุญแจ validator ของ TPIX Chain (ฝั่งกุญแจ validator)")
    p.add_argument("--staking-wallet", required=True, help="กระเป๋าที่ stake ชั้น Validator")
    p.add_argument("--data-dir", default=".", help="data-dir ของ polygon-edge (มี consensus/validator.key)")
    p.add_argument("--key-file", help="ระบุไฟล์ validator.key ตรง ๆ แทน --data-dir")
    p.add_argument("--edge", help='คำสั่งเรียก polygon-edge เช่น "docker exec tpix-node polygon-edge"')
    p.add_argument("--edge-data-dir", help="data-dir ตามที่ polygon-edge มองเห็น (ในคอนเทนเนอร์มักเป็น /data)")
    p.add_argument("--bls", help="BLS public key (ถ้าไม่ใช้ --edge)")
    p.add_argument("--node-id", help="libp2p node ID (ถ้าไม่ใช้ --edge)")
    p.add_argument("--chain-id", type=int, default=CHAIN_ID)
    p.add_argument("--signed-at", help=argparse.SUPPRESS)  # ใช้ในเทสต์เท่านั้น
    args = p.parse_args(argv)

    try:
        result = build(args)
    except (ValueError, OSError, subprocess.SubprocessError) as e:
        print("✗ " + str(e), file=sys.stderr)
        return 1

    print(json.dumps(result, separators=(",", ":")))
    print("✓ คัดลอกบรรทัด JSON ด้านบนไปวางในโปรแกรม TPIX Master Node → แท็บ Validator → "
          "'โหนดอยู่บนเซิร์ฟเวอร์' แล้วเซ็นด้วยกระเป๋าที่ stake ภายใน 30 นาที", file=sys.stderr)
    print("  ที่อยู่ validator: %s · node ID: %s" % (result["validator_address"], result["node_id"]), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
