#!/usr/bin/env python3
# ══════════════════════════════════════════════════════════════════════════════
#  tpix-nginx-ban — เติม/ลบที่อยู่ใน tpix-banned.map แล้ว reload nginx
#  ติดตั้งที่ /usr/local/sbin/tpix-nginx-ban   (เรียกโดย fail2ban action nginx-tpix-banned)
# ══════════════════════════════════════════════════════════════════════════════
#
#  ทำไมแบนที่ nginx ไม่ใช่ iptables
#    origin รับเฉพาะ IP ของ Cloudflare (allow-cloudflare-only.sh) — แพ็กเก็ตทุกใบที่มาถึง
#    มีต้นทางเป็น Cloudflare กฎ iptables ที่ระบุ IP ผู้ใช้จึงไม่ตรงกับแพ็กเก็ตใดเลย
#    (เห็นบน lab/rpc-ban-lab.sh: แบนด้วย iptables-multiport แล้วคำขอยังได้ 200)
#    ที่อยู่ผู้ใช้จริงมีอยู่ที่เดียวคือ $remote_addr ของ nginx หลัง real_ip
#    → geo $banned_ip { include tpix-banned.map; } + if ($banned_ip) { return 403; } ใน vhost
#
#  หน่วยที่แบน
#    IPv4            → ที่อยู่นั้น
#    IPv6            → /64 ที่ที่อยู่นั้นอยู่ (ผู้ใช้หนึ่งรายถือทั้ง /64 และหมุนที่อยู่ได้ทุกคำขอ)
#    ::ffff:a.b.c.d  → a.b.c.d
#
#  ใช้:
#    tpix-nginx-ban add <ที่อยู่>       # แบน — มีอยู่แล้วไม่ทำอะไร ไม่ reload
#    tpix-nginx-ban remove <ที่อยู่>    # เลิกแบน — ลบเฉพาะบรรทัดที่สคริปต์นี้เขียน
#    tpix-nginx-ban flush               # ลบทุกบรรทัดที่สคริปต์นี้เขียน (fail2ban start/stop)
#    tpix-nginx-ban list                # พิมพ์รายการ (มือ / สคริปต์)
#
#  บรรทัดที่ใส่มือ (ไม่มีเครื่องหมาย "# tpix-nginx-ban") สคริปต์นี้ไม่แตะเลย
#
#  สามอย่างที่ต้องไม่เกิด:
#    1. เขียนบรรทัดที่ nginx อ่านไม่ได้ = nginx สตาร์ทไม่ขึ้นรอบหน้า = RPC ดับ
#       → รับเฉพาะที่อยู่ที่ ipaddress ของ Python ถอดได้ เขียนรูป canonical เท่านั้น
#         เขียนเสร็จรัน nginx -t ทันที ไม่ผ่าน = คืนไฟล์เดิมแล้ว exit 1
#    2. reload ถี่ตามจำนวนที่อยู่ที่ถูกแบน (บอตเน็ต 500 ตัว = reload 500 ครั้ง)
#       → reload ไม่เกิน 1 ครั้งต่อ --min-interval วินาที ครั้งที่ถี่กว่านั้นรวมเป็นครั้งเดียวที่ทำทีหลัง
#    3. สองคำสั่งเขียนไฟล์พร้อมกัน → flock ทั้งช่วง อ่าน-เขียน-ทดสอบ
#
#  ⚠️ `systemctl reload nginx` คืนค่าสำเร็จแม้ config ใหม่ถูกปฏิเสธ (RUNBOOK ตารางกับดัก)
#     สคริปต์นี้รัน nginx -t ก่อนทุกครั้ง แต่สาเหตุที่ nginx -t จับไม่ได้ (เปลี่ยนชนิด/กุญแจของโซนเดิม)
#     ยังหลุดได้ — ถ้าแบนแล้วไม่มีผล ให้อ่าน /var/log/nginx/error.log
#
#  Developed by Xman Studio.
# ══════════════════════════════════════════════════════════════════════════════
import argparse
import datetime
import fcntl
import ipaddress
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time

MARK = "# tpix-nginx-ban"
DEFAULT_MAP = "/etc/nginx/conf.d/tpix-banned.map"
DEFAULT_STATE = "/run/tpix-nginx-ban"
DEFAULT_LOG = "/var/log/tpix-nginx-ban.log"
DEFAULT_TEST = "nginx -t"
DEFAULT_RELOAD = "systemctl reload nginx"

# ยอมรับเฉพาะตัวอักษรที่ที่อยู่ IP มีได้ — ค่านี้ถูกเขียนลงไฟล์ config ของ nginx
ADDR_CHARS = re.compile(r"^[0-9A-Fa-f:.]{2,45}(?:/[0-9]{1,3})?$")
# บรรทัดในไฟล์: <ที่อยู่หรือ CIDR> 1; [# หมายเหตุ]
ENTRY = re.compile(r"^\s*([0-9A-Fa-f:./]+)\s+1\s*;\s*(#.*)?$")


class Refused(Exception):
    pass


def canonical(text):
    """ที่อยู่/CIDR → ข้อความที่จะเขียนลงไฟล์ · โยน Refused ถ้าไม่ใช่ของที่แบนได้"""
    text = (text or "").strip()
    if not ADDR_CHARS.match(text):
        raise Refused("ไม่ใช่ที่อยู่ IP: %r" % text[:60])
    try:
        if "/" in text:
            net = ipaddress.ip_network(text, strict=False)
        else:
            ip = ipaddress.ip_address(text)
            if ip.version == 6 and ip.ipv4_mapped is not None:
                ip = ip.ipv4_mapped
            net = ipaddress.ip_network("%s/%d" % (ip, 32 if ip.version == 4 else 64), strict=False)
    except ValueError as e:
        raise Refused("ถอดที่อยู่ไม่ได้: %s" % e)

    if net.version == 6:
        mapped = net.network_address.ipv4_mapped
        if mapped is not None and net.prefixlen >= 96:
            net = ipaddress.ip_network("%s/%d" % (mapped, net.prefixlen - 96), strict=False)
        elif net.prefixlen > 64:
            # ที่อยู่เดี่ยวหรือช่วงที่แคบกว่า /64 → แบนทั้ง /64
            net = ipaddress.ip_network("%s/64" % net.network_address, strict=False)

    if net.version == 4 and net.prefixlen < 16:
        raise Refused("ช่วงกว้างเกินไป (%s) — IPv4 รับแคบสุด /32 กว้างสุด /16" % net)
    if net.version == 6 and net.prefixlen < 32:
        raise Refused("ช่วงกว้างเกินไป (%s) — IPv6 รับแคบสุด /64 กว้างสุด /32" % net)

    probe = net.network_address
    if probe.is_unspecified or probe.is_loopback or probe.is_multicast:
        raise Refused("ไม่แบนที่อยู่ชนิดนี้: %s" % net)
    if net.version == 6 and ipaddress.ip_address("::1") in net:
        raise Refused("ไม่แบนช่วงที่ครอบ loopback: %s" % net)

    if net.version == 4 and net.prefixlen == 32:
        return str(net.network_address)
    return str(net)


def entry_key(line):
    """บรรทัดในไฟล์ → (กุญแจ canonical หรือ None, เป็นบรรทัดของสคริปต์นี้ไหม)"""
    m = ENTRY.match(line)
    if not m:
        return None, False
    try:
        key = canonical(m.group(1))
    except Refused:
        key = None
    return key, bool(m.group(2)) and m.group(2).startswith(MARK)


class Banner:
    def __init__(self, args):
        self.map = args.map
        self.state = args.state_dir
        self.logfile = args.log
        self.test_cmd = args.test_cmd
        self.reload_cmd = args.reload_cmd
        self.min_interval = max(0.0, args.min_interval)
        self.stamp = os.path.join(self.state, "last-reload")
        self.pending = os.path.join(self.state, "reload-pending")
        os.makedirs(self.state, mode=0o700, exist_ok=True)

    # ── เบ็ดเตล็ด ──────────────────────────────────────────────────────────────
    def log(self, msg):
        line = "%s %s\n" % (datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), msg)
        try:
            with open(self.logfile, "a", encoding="utf-8") as f:
                f.write(line)
        except OSError:
            pass

    def lock(self):
        fd = os.open(os.path.join(self.state, "lock"), os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        return fd

    def run(self, cmd):
        try:
            p = subprocess.run(shlex.split(cmd), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, timeout=30)
            return p.returncode, p.stdout.decode("utf-8", "replace").strip()
        except (OSError, subprocess.SubprocessError) as e:
            return 127, str(e)

    def read(self):
        with open(self.map, "r", encoding="utf-8") as f:
            return f.read()

    def write(self, text):
        """เขียนทับแบบ atomic — nginx ที่ reload พร้อมกันพอดีจะเห็นไฟล์เก่าหรือไฟล์ใหม่ ไม่เห็นไฟล์ครึ่งเดียว"""
        st = os.stat(self.map)
        fd, tmp = tempfile.mkstemp(prefix=".tpix-banned.", dir=os.path.dirname(self.map) or ".")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(text)
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, st.st_mode & 0o7777)
            try:
                os.chown(tmp, st.st_uid, st.st_gid)
            except OSError:
                pass
            os.replace(tmp, self.map)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

    # ── reload: ไม่เกิน 1 ครั้งต่อ min_interval ────────────────────────────────
    def since_reload(self):
        try:
            return time.time() - os.stat(self.stamp).st_mtime
        except OSError:
            return float("inf")

    def reload_now(self, why):
        rc, out = self.run(self.reload_cmd)
        with open(self.stamp, "w") as f:
            f.write(str(time.time()))
        if rc != 0:
            self.log("RELOAD-FAIL (%s) rc=%d %s" % (why, rc, out[:300]))
            return False
        self.log("RELOAD (%s)" % why)
        return True

    def request_reload(self, why):
        """เรียกขณะถือ lock · คืน False เมื่อสั่ง reload แล้วไม่สำเร็จ"""
        wait = self.min_interval - self.since_reload()
        if wait <= 0:
            return self.reload_now(why)
        try:
            # มีตัวรอ reload อยู่แล้ว (และยังไม่ค้างเกิน 1 นาที) — ตัวนั้นจะเก็บการแก้ครั้งนี้ไปด้วย
            if time.time() - os.stat(self.pending).st_mtime < 60:
                self.log("RELOAD-JOIN (%s)" % why)
                return True
        except OSError:
            pass
        with open(self.pending, "w") as f:
            f.write(str(os.getpid()))
        self.log("RELOAD-DEFER %.1fs (%s)" % (wait, why))
        self.spawn_deferred(wait)
        return True

    def spawn_deferred(self, wait):
        """ตัวรอ reload — หลุดจาก fail2ban ทั้ง session และ stdio ไม่งั้น fail2ban จะรอจนมันจบ"""
        if os.fork() != 0:
            return
        try:
            os.setsid()
            if os.fork() != 0:
                os._exit(0)
            null = os.open(os.devnull, os.O_RDWR)
            for fd in (0, 1, 2):
                os.dup2(null, fd)
            os.closerange(3, 256)
            time.sleep(wait)
            fd = self.lock()
            try:
                try:
                    os.unlink(self.pending)
                except OSError:
                    pass
                rc, out = self.run(self.test_cmd)
                if rc != 0:
                    self.log("RELOAD-SKIP config ไม่ผ่าน nginx -t: %s" % out[-300:])
                else:
                    self.reload_now("deferred")
            finally:
                os.close(fd)
        finally:
            os._exit(0)

    # ── คำสั่ง ─────────────────────────────────────────────────────────────────
    def apply(self, old, new, what):
        """เขียน new → nginx -t → ไม่ผ่านคืน old · คืน exit code"""
        self.write(new)
        rc, out = self.run(self.test_cmd)
        if rc != 0:
            self.write(old)
            self.log("ROLLBACK %s — nginx -t ไม่ผ่าน: %s" % (what, out[-300:]))
            sys.stderr.write("tpix-nginx-ban: nginx -t ไม่ผ่านหลัง %s — คืนไฟล์เดิมแล้ว\n%s\n" % (what, out[-600:]))
            return 1
        self.log(what)
        if not self.request_reload(what):
            sys.stderr.write("tpix-nginx-ban: %s เขียนไฟล์แล้ว แต่ reload nginx ไม่สำเร็จ\n" % what)
            return 1
        return 0

    def add(self, addr):
        key = canonical(addr)
        fd = self.lock()
        try:
            old = self.read()
            for line in old.splitlines():
                k, _ = entry_key(line)
                if k == key:
                    self.log("ADD %s — มีอยู่แล้ว" % key)
                    return 0
            new = old if old.endswith("\n") or old == "" else old + "\n"
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            new += "%s 1; %s %s\n" % (key, MARK, stamp)
            return self.apply(old, new, "ADD %s" % key)
        finally:
            os.close(fd)

    def remove(self, addr):
        key = canonical(addr)
        fd = self.lock()
        try:
            old = self.read()
            kept, dropped = [], 0
            for line in old.splitlines(True):
                k, ours = entry_key(line)
                if ours and k == key:
                    dropped += 1
                else:
                    kept.append(line)
            if dropped == 0:
                self.log("REMOVE %s — ไม่มีบรรทัดของสคริปต์นี้" % key)
                return 0
            return self.apply(old, "".join(kept), "REMOVE %s" % key)
        finally:
            os.close(fd)

    def flush(self):
        fd = self.lock()
        try:
            old = self.read()
            kept, dropped = [], 0
            for line in old.splitlines(True):
                _, ours = entry_key(line)
                if ours:
                    dropped += 1
                else:
                    kept.append(line)
            if dropped == 0:
                return 0
            return self.apply(old, "".join(kept), "FLUSH %d บรรทัด" % dropped)
        finally:
            os.close(fd)

    def list(self):
        for line in self.read().splitlines():
            k, ours = entry_key(line)
            if k is not None:
                print("%-44s %s" % (k, "fail2ban" if ours else "ใส่มือ"))
        return 0


def main(argv=None):
    env = os.environ.get
    ap = argparse.ArgumentParser(prog="tpix-nginx-ban", description="แบน/เลิกแบนที่อยู่ที่ชั้น nginx (geo $banned_ip)")
    ap.add_argument("--map", default=env("TPIX_BAN_MAP", DEFAULT_MAP))
    ap.add_argument("--state-dir", default=env("TPIX_BAN_STATE", DEFAULT_STATE))
    ap.add_argument("--log", default=env("TPIX_BAN_LOG", DEFAULT_LOG))
    ap.add_argument("--test-cmd", default=env("TPIX_BAN_TEST_CMD", DEFAULT_TEST))
    ap.add_argument("--reload-cmd", default=env("TPIX_BAN_RELOAD_CMD", DEFAULT_RELOAD))
    ap.add_argument("--min-interval", type=float, default=float(env("TPIX_BAN_MIN_INTERVAL", "5")),
                    help="วินาทีขั้นต่ำระหว่าง reload สองครั้ง (ค่าเริ่มต้น 5)")
    ap.add_argument("command", choices=["add", "remove", "flush", "list", "canonical"])
    ap.add_argument("address", nargs="?")
    args = ap.parse_args(argv)

    try:
        if args.command == "canonical":
            print(canonical(args.address))
            return 0
        b = Banner(args)
        if args.command in ("add", "remove"):
            if not args.address:
                ap.error("%s ต้องมีที่อยู่" % args.command)
            return getattr(b, args.command)(args.address)
        return getattr(b, args.command)()
    except Refused as e:
        sys.stderr.write("tpix-nginx-ban: ปฏิเสธ — %s\n" % e)
        return 2
    except OSError as e:
        sys.stderr.write("tpix-nginx-ban: %s\n" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
