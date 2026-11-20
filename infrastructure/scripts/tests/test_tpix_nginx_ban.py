"""tpix-nginx-ban.py — ตรรกะของตัวเขียน tpix-banned.map (ไม่มี nginx: test/reload เป็นคำสั่งปลอม)

ส่วนที่ต้องมี nginx + fail2ban ตัวจริงอยู่ที่ infrastructure/lab/rpc-ban-lab.sh
"""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location('ban', Path(__file__).parents[1] / 'tpix-nginx-ban.py')
ban = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ban)

HEADER = "# ใส่มือ\n198.51.100.7 1;\n2001:db8:aaaa::/48 1;   # ถาวร\n"


class CanonicalTests(unittest.TestCase):
    def test_ipv4_stays_one_address(self):
        self.assertEqual(ban.canonical('203.0.113.99'), '203.0.113.99')
        self.assertEqual(ban.canonical(' 203.0.113.99\n'), '203.0.113.99')
        self.assertEqual(ban.canonical('203.0.113.99/32'), '203.0.113.99')

    def test_ipv6_becomes_its_64(self):
        want = '2001:db8:0:1::/64'
        for a in ('2001:db8:0:1::', '2001:db8:0:1::5', '2001:DB8:0:1:AAAA:BBBB:CCCC:DDDD',
                  '2001:0db8:0000:0001:0000:0000:0000:0001', '2001:db8:0:1::/64', '2001:db8:0:1::9/128',
                  '2001:db8:0:1:ffff::/80'):
            self.assertEqual(ban.canonical(a), want, a)
        self.assertNotEqual(ban.canonical('2001:db8:0:2::1'), want)
        self.assertEqual(ban.canonical('2001:db8::1'), '2001:db8::/64')

    def test_ipv4_mapped_is_the_ipv4(self):
        self.assertEqual(ban.canonical('::ffff:203.0.113.99'), '203.0.113.99')
        self.assertEqual(ban.canonical('::ffff:cb00:7163'), '203.0.113.99')
        self.assertEqual(ban.canonical('::ffff:203.0.113.99/128'), '203.0.113.99')

    def test_manual_ranges_within_limits(self):
        self.assertEqual(ban.canonical('5.6.7.9/24'), '5.6.7.0/24')
        self.assertEqual(ban.canonical('2001:db8:5::1/48'), '2001:db8:5::/48')

    def test_refuses_what_must_never_reach_the_nginx_config(self):
        for junk in ('', ' ', 'abc', '1.2.3', '1.2.3.4.5', '999.1.1.1', '1.2.3.4;', '1.2.3.4 1; }', '1.2.3.4\n5.6.7.8',
                     '$(reboot)', '`id`', '1.2.3.4/33', '2001:db8::/129', '2001:db8::1%eth0', '[2001:db8::1]',
                     'include /etc/passwd', '..', ':::', 'gggg::1', '1.2.3.4/', '/24', 'f' * 46, None):
            with self.assertRaises(ban.Refused, msg=repr(junk)):
                ban.canonical(junk)

    def test_refuses_loopback_unspecified_and_wide_ranges(self):
        for a in ('127.0.0.1', '127.0.0.0/16', '0.0.0.0', '::1', '::', '0:0:0:0::', '::/64', 'ff02::1', '224.0.0.1',
                  '10.0.0.0/8', '0.0.0.0/0', '2001::/16', '::/0', '1.2.3.4/15'):
            with self.assertRaises(ban.Refused, msg=a):
                ban.canonical(a)


class MapFileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)
        self.map = self.dir / 'tpix-banned.map'
        self.map.write_text(HEADER, encoding='utf-8')
        self.reloads = self.dir / 'reloads'

    def tearDown(self):
        self.temp.cleanup()

    def run_cmd(self, *argv, test_ok=True, interval='0'):
        # reload ปลอม = เติมหนึ่งบรรทัดลงไฟล์ นับได้ว่า reload กี่ครั้ง
        counter = self.dir / 'count.py'
        counter.write_text("import sys\nopen(sys.argv[1], 'a').write('r\\n')\n", encoding='utf-8')
        return ban.main([
            '--map', str(self.map), '--state-dir', str(self.dir / 'state'), '--log', str(self.dir / 'ban.log'),
            '--test-cmd', '%s -c "raise SystemExit(%d)"' % (sys.executable, 0 if test_ok else 1),
            '--reload-cmd', '%s %s %s' % (sys.executable, counter, self.reloads),
            '--min-interval', interval, *argv,
        ])

    def reload_count(self):
        return len(self.reloads.read_text().splitlines()) if self.reloads.exists() else 0

    def entries(self):
        return [l for l in self.map.read_text(encoding='utf-8').splitlines() if ban.MARK in l]

    def test_add_writes_one_canonical_line_and_reloads(self):
        self.assertEqual(self.run_cmd('add', '2001:db8:0:1::5'), 0)
        self.assertEqual(len(self.entries()), 1)
        self.assertTrue(self.entries()[0].startswith('2001:db8:0:1::/64 1; ' + ban.MARK))
        self.assertTrue(self.map.read_text(encoding='utf-8').startswith(HEADER), 'บรรทัดใส่มือต้องอยู่ครบ')
        self.assertEqual(self.reload_count(), 1)

    def test_add_twice_is_a_no_op_without_reload(self):
        self.run_cmd('add', '203.0.113.99')
        self.assertEqual(self.run_cmd('add', '203.0.113.99'), 0)
        # ที่อยู่อื่นใน /64 ที่แบนอยู่แล้วก็ไม่ต้องเขียนซ้ำ
        self.run_cmd('add', '2001:db8:0:1::5')
        self.assertEqual(self.run_cmd('add', '2001:db8:0:1::6'), 0)
        self.assertEqual(len(self.entries()), 2)
        self.assertEqual(self.reload_count(), 2)

    def test_add_of_a_manual_entry_changes_nothing(self):
        self.assertEqual(self.run_cmd('add', '198.51.100.7'), 0)
        self.assertEqual(self.entries(), [])
        self.assertEqual(self.reload_count(), 0)

    def test_remove_only_touches_own_lines(self):
        self.run_cmd('add', '203.0.113.99')
        self.run_cmd('add', '2001:db8:0:1::5')
        self.assertEqual(self.run_cmd('remove', '2001:db8:0:1::'), 0)
        self.assertEqual(len(self.entries()), 1)
        self.assertEqual(self.run_cmd('remove', '198.51.100.7'), 0, 'บรรทัดใส่มือ: ไม่ลบ ไม่ error')
        self.assertEqual(self.run_cmd('remove', '192.0.2.1'), 0, 'ไม่มีในไฟล์: ไม่ error')
        self.assertIn('198.51.100.7 1;', self.map.read_text(encoding='utf-8'))
        self.assertEqual(self.reload_count(), 3)

    def test_flush_drops_every_own_line_and_keeps_manual_ones(self):
        for a in ('203.0.113.1', '203.0.113.2', '2001:db8:0:1::5'):
            self.run_cmd('add', a)
        self.assertEqual(self.run_cmd('flush'), 0)
        self.assertEqual(self.map.read_text(encoding='utf-8'), HEADER)
        self.assertEqual(self.run_cmd('flush'), 0)
        self.assertEqual(self.reload_count(), 4, 'flush รอบสองไม่มีอะไรให้ลบ ไม่ reload')

    def test_failed_config_test_restores_the_file(self):
        self.assertEqual(self.run_cmd('add', '203.0.113.99', test_ok=False), 1)
        self.assertEqual(self.map.read_text(encoding='utf-8'), HEADER)
        self.assertEqual(self.reload_count(), 0)
        self.run_cmd('add', '203.0.113.99')
        before = self.map.read_text(encoding='utf-8')
        self.assertEqual(self.run_cmd('remove', '203.0.113.99', test_ok=False), 1)
        self.assertEqual(self.map.read_text(encoding='utf-8'), before, 'เลิกแบนไม่สำเร็จ = ยังแบนอยู่')

    def test_garbage_never_reaches_the_file(self):
        self.assertEqual(self.run_cmd('add', '1.2.3.4 1; } include /etc/shadow;'), 2)
        self.assertEqual(self.run_cmd('add', '127.0.0.1'), 2)
        self.assertEqual(self.map.read_text(encoding='utf-8'), HEADER)
        self.assertEqual(self.reload_count(), 0)

    def test_missing_map_is_an_error_not_a_new_file(self):
        self.map.unlink()
        self.assertEqual(self.run_cmd('add', '203.0.113.99'), 1)
        self.assertFalse(self.map.exists())

    def test_file_mode_survives_the_rewrite(self):
        os.chmod(self.map, 0o640)
        self.run_cmd('add', '203.0.113.99')
        self.assertEqual(os.stat(self.map).st_mode & 0o777, 0o640)

    def test_burst_of_bans_is_coalesced_into_few_reloads(self):
        for i in range(1, 21):
            self.assertEqual(self.run_cmd('add', '203.0.113.%d' % i, interval='4'), 0)
        self.assertEqual(len(self.entries()), 20, 'ทุกที่อยู่ลงไฟล์ทันที')
        self.assertEqual(self.reload_count(), 1, 'reload ทันทีครั้งเดียว ที่เหลือรอรวม')
        deadline = time.time() + 15
        while self.reload_count() < 2 and time.time() < deadline:
            time.sleep(0.1)
        time.sleep(0.5)
        self.assertEqual(self.reload_count(), 2, 'ที่เหลือทั้งหมดรวมเป็น reload ครั้งเดียว')
        self.assertFalse((self.dir / 'state' / 'reload-pending').exists())


if __name__ == '__main__':
    unittest.main()
