"""
เทสต์ validator_sign_binding.py — รัน: python3 -m unittest discover -s infrastructure/validator

ลายเซ็นต้อง "ตรงทุกไบต์" กับ ethers v6 (Wallet.signMessage) ที่แอปมาสเตอร์โหนดใช้
และที่เว็บตรวจด้วย ecrecover — ค่าอ้างอิงด้านล่างสร้างจาก ethers 6 จริง (2026-10-22)
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import validator_sign_binding as vsb  # noqa: E402

TEST_KEY = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
TEST_ADDR = "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"
BLS = "0x" + "ab" * 48
NODE_ID = "16Uiu2HAmSmFLK2z9HhZifQ3xaZmbZkZbT3hcEodRvVdX9tNnB8xv"
WALLET = "0xabcdef0000000000000000000000000000000001"

# ethers.Wallet(TEST_KEY).signMessage(ข้อความผูกด้านล่าง)
ETHERS_BINDING_SIG = ("0x60d005529293b7c4a129e0f5fbd7e3f7fda1bf0aa75ffb0b4f5dceda70fbe016"
                      "0facf59bca2d2dae0f6340aa5114400c153c2fc90355af644eb8171828036d181b")
# ethers.Wallet(0x…01).signMessage("hello")
ETHERS_HELLO_SIG = ("0xe5ddc160e4c8f92de507c7db9b982d4f9b7197bfa421864aeadc586bc96b09ae"
                    "0ba0c5b131650ae4994cff1839341d00f3735ef5abc62ac8fe2cf50f65208e2a1b")


class CryptoTest(unittest.TestCase):
    def test_keccak256_known_vectors(self):
        self.assertEqual(vsb.keccak256(b"").hex(),
                         "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        self.assertEqual(vsb.keccak256(b"abc").hex(),
                         "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        # ยาวเท่า rate-1 และข้ามบล็อก — ตำแหน่งเติมบิตที่พลาดง่ายที่สุด
        self.assertEqual(len(vsb.keccak256(b"x" * 135)), 32)
        self.assertNotEqual(vsb.keccak256(b"x" * 135), vsb.keccak256(b"x" * 136))

    def test_address_derivation(self):
        self.assertEqual(vsb.address_of(1), "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf")
        self.assertEqual(vsb.address_of(int(TEST_KEY, 16)), TEST_ADDR)

    def test_signatures_match_ethers_byte_for_byte(self):
        self.assertEqual(vsb.personal_sign(1, "hello"), ETHERS_HELLO_SIG)
        message = vsb.binding_message(4289, WALLET, TEST_ADDR, BLS, NODE_ID, 1761123456)
        self.assertEqual(vsb.personal_sign(int(TEST_KEY, 16), message), ETHERS_BINDING_SIG)

    def test_message_matches_the_website_format(self):
        # ตรงกับ ThaiXTrade ValidatorKeyBindingTest::test_the_message_is_exactly_what_the_desktop_app_signs
        self.assertEqual(
            vsb.binding_message(4289, "0xABCDEF0000000000000000000000000000000001",
                                "0x00AFfa6379fBd969CBe5906cDeee793960a500DA", BLS.upper().replace("0X", "0x"),
                                NODE_ID, 1761123456),
            "TPIX Chain validator key binding\n"
            "chain_id: 4289\n"
            "staking_wallet: 0xabcdef0000000000000000000000000000000001\n"
            "validator_address: 0x00affa6379fbd969cbe5906cdeee793960a500da\n"
            "bls_public_key: " + BLS + "\n"
            "node_id: " + NODE_ID + "\n"
            "signed_at: 1761123456",
        )


class CliTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.dir, "consensus"))
        # รูปแบบเดียวกับที่ polygon-edge 0.9 เขียน: hex 64 ตัว ไม่มี 0x ไม่มีขึ้นบรรทัด
        with open(os.path.join(self.dir, "consensus", "validator.key"), "w") as f:
            f.write(TEST_KEY)

    def run_cli(self, *extra):
        args = ["--staking-wallet", WALLET, "--data-dir", self.dir, "--signed-at", "1761123456", *extra]
        with mock.patch("sys.stdout") as out, mock.patch("sys.stderr") as err:
            code = vsb.main(args)
        printed = "".join(c.args[0] for c in out.write.call_args_list)
        errors = "".join(c.args[0] for c in err.write.call_args_list)
        return code, printed, errors

    def test_prints_a_binding_the_app_can_paste(self):
        code, out, _ = self.run_cli("--bls", BLS, "--node-id", NODE_ID)
        self.assertEqual(code, 0)
        blob = json.loads(out.strip())
        self.assertEqual(blob["validator_address"], TEST_ADDR)
        self.assertEqual(blob["validator_signature"], ETHERS_BINDING_SIG)
        self.assertEqual(blob["tpix_validator_binding"], 1)
        self.assertEqual(blob["chain_id"], 4289)

    def test_reads_bls_and_node_id_from_polygon_edge(self):
        fake = json.dumps({"address": TEST_ADDR.upper().replace("0X", "0x"), "bls": BLS, "node_id": NODE_ID})
        done = subprocess.CompletedProcess([], 0, stdout="\n" + fake + "\n", stderr="")
        with mock.patch("subprocess.run", return_value=done) as run:
            code, out, _ = self.run_cli("--edge", "docker exec tpix-node polygon-edge", "--edge-data-dir", "/data")
        self.assertEqual(code, 0)
        self.assertEqual(run.call_args.args[0],
                         ["docker", "exec", "tpix-node", "polygon-edge", "secrets", "output", "--json", "--data-dir", "/data"])
        self.assertEqual(json.loads(out.strip())["bls_public_key"], BLS)

    def test_refuses_a_bls_from_another_data_dir(self):
        fake = json.dumps({"address": "0x" + "9" * 40, "bls": BLS, "node_id": NODE_ID})
        done = subprocess.CompletedProcess([], 0, stdout=fake, stderr="")
        with mock.patch("subprocess.run", return_value=done):
            code, out, err = self.run_cli("--edge", "polygon-edge")
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn("คนละ data-dir", err)

    def test_rejects_bad_input_without_signing(self):
        for extra, needle in [
            (["--bls", "0x1234", "--node-id", NODE_ID], "BLS"),
            (["--bls", BLS, "--node-id", "not-a-peer"], "node ID"),
            ([], "--edge"),
        ]:
            code, out, err = self.run_cli(*extra)
            self.assertEqual(code, 1)
            self.assertEqual(out, "")
            self.assertIn(needle, err)

    def test_refuses_using_the_staking_wallet_as_the_validator_key(self):
        with mock.patch("sys.stdout"), mock.patch("sys.stderr") as err:
            code = vsb.main(["--staking-wallet", TEST_ADDR, "--data-dir", self.dir, "--bls", BLS, "--node-id", NODE_ID])
        self.assertEqual(code, 1)
        self.assertIn("ไม่ใช่กระเป๋าที่ stake", "".join(c.args[0] for c in err.write.call_args_list))

    def test_bad_key_file(self):
        with open(os.path.join(self.dir, "consensus", "validator.key"), "w") as f:
            f.write("not-hex")
        code, _, err = self.run_cli("--bls", BLS, "--node-id", NODE_ID)
        self.assertEqual(code, 1)
        self.assertIn("hex 64", err)


if __name__ == "__main__":
    unittest.main()
