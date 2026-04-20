const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * ทดสอบ USDT_TPIX (Bridged Tether ERC-20 บน TPIX Chain)
 *
 * Coverage:
 *   - decimals = 6 (เหมือน Tether จริง)
 *   - bridgeMint: whitelist-only
 *   - bridgeBurn: user burn ตัวเอง → emit event สำหรับ relayer
 *   - setBridge: owner-only
 *   - pause / unpause: owner-only, บล็อก transfer
 *   - totalEverMinted / totalEverBurned tracking
 */
describe("USDT_TPIX", function () {
    async function deployFixture() {
        const [owner, relayer, alice, bob] = await ethers.getSigners();
        const USDT = await ethers.getContractFactory("USDT_TPIX");
        const usdt = await USDT.deploy();
        await usdt.waitForDeployment();

        // whitelist relayer
        await usdt.setBridge(relayer.address, true);

        return { usdt, owner, relayer, alice, bob };
    }

    describe("metadata", function () {
        it("uses 6 decimals matching real Tether", async function () {
            const { usdt } = await loadFixture(deployFixture);
            expect(await usdt.decimals()).to.equal(6);
            expect(await usdt.symbol()).to.equal("USDT");
        });
    });

    describe("setBridge()", function () {
        it("only owner can add/remove bridge", async function () {
            const { usdt, alice } = await loadFixture(deployFixture);
            await expect(usdt.connect(alice).setBridge(alice.address, true))
                .to.be.revertedWithCustomError(usdt, "OwnableUnauthorizedAccount");
        });

        it("emits BridgeSet event", async function () {
            const { usdt, bob } = await loadFixture(deployFixture);
            await expect(usdt.setBridge(bob.address, true))
                .to.emit(usdt, "BridgeSet")
                .withArgs(bob.address, true);
        });
    });

    describe("bridgeMint()", function () {
        const TX_HASH = "0x" + "a".repeat(64);

        it("mints when called by whitelisted relayer", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseUnits("1000", 6); // $1000

            await expect(usdt.connect(relayer).bridgeMint(alice.address, amount, TX_HASH))
                .to.emit(usdt, "Minted")
                .withArgs(alice.address, amount, TX_HASH);

            expect(await usdt.balanceOf(alice.address)).to.equal(amount);
            expect(await usdt.totalEverMinted()).to.equal(amount);
        });

        it("reverts when called by non-bridge", async function () {
            const { usdt, alice } = await loadFixture(deployFixture);
            await expect(
                usdt.connect(alice).bridgeMint(alice.address, 1000n, TX_HASH)
            ).to.be.revertedWith("USDT_TPIX: not a bridge");
        });

        it("reverts on zero recipient", async function () {
            const { usdt, relayer } = await loadFixture(deployFixture);
            await expect(
                usdt.connect(relayer).bridgeMint(ethers.ZeroAddress, 1000n, TX_HASH)
            ).to.be.revertedWith("USDT_TPIX: zero recipient");
        });

        it("reverts on zero amount", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await expect(
                usdt.connect(relayer).bridgeMint(alice.address, 0, TX_HASH)
            ).to.be.revertedWith("USDT_TPIX: zero amount");
        });

        it("accumulates totalEverMinted across multiple mints", async function () {
            const { usdt, relayer, alice, bob } = await loadFixture(deployFixture);
            const a = ethers.parseUnits("500", 6);
            const b = ethers.parseUnits("300", 6);
            await usdt.connect(relayer).bridgeMint(alice.address, a, TX_HASH);
            await usdt.connect(relayer).bridgeMint(bob.address, b, TX_HASH);
            expect(await usdt.totalEverMinted()).to.equal(a + b);
        });
    });

    describe("bridgeBurn()", function () {
        it("user burns own balance and emits event", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseUnits("100", 6);
            await usdt.connect(relayer).bridgeMint(alice.address, amount, "0x" + "1".repeat(64));

            const targetChainAddr = "0x000000000000000000000000000000000000dEaD";
            await expect(
                usdt.connect(alice).bridgeBurn(amount, targetChainAddr, "0xABC123deadbeef")
            )
                .to.emit(usdt, "Burned")
                .withArgs(alice.address, amount, targetChainAddr, "0xABC123deadbeef");

            expect(await usdt.balanceOf(alice.address)).to.equal(0n);
            expect(await usdt.totalEverBurned()).to.equal(amount);
        });

        it("reverts on empty target address string", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await usdt.connect(relayer).bridgeMint(alice.address, 100n, "0x" + "2".repeat(64));

            await expect(
                usdt.connect(alice).bridgeBurn(100n, alice.address, "")
            ).to.be.revertedWith("USDT_TPIX: empty target");
        });
    });

    describe("pause/unpause", function () {
        it("only owner can pause", async function () {
            const { usdt, alice } = await loadFixture(deployFixture);
            await expect(usdt.connect(alice).pause())
                .to.be.revertedWithCustomError(usdt, "OwnableUnauthorizedAccount");
        });

        it("paused blocks transfers and mint", async function () {
            const { usdt, relayer, alice, bob } = await loadFixture(deployFixture);
            const amount = ethers.parseUnits("100", 6);
            await usdt.connect(relayer).bridgeMint(alice.address, amount, "0x" + "3".repeat(64));

            await usdt.pause();

            await expect(usdt.connect(alice).transfer(bob.address, 1n))
                .to.be.revertedWithCustomError(usdt, "EnforcedPause");

            await expect(
                usdt.connect(relayer).bridgeMint(bob.address, 1n, "0x" + "4".repeat(64))
            ).to.be.revertedWithCustomError(usdt, "EnforcedPause");
        });

        it("unpause restores operations", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await usdt.pause();
            await usdt.unpause();

            await expect(
                usdt.connect(relayer).bridgeMint(alice.address, 1n, "0x" + "5".repeat(64))
            ).to.not.be.reverted;
        });
    });
});
