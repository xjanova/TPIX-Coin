const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * ทดสอบ USDT_TPIX (Bridged Tether ERC-20 บน TPIX Chain)
 *
 * Coverage:
 *   - decimals = 6 (เหมือน Tether จริง)
 *   - bridgeMint: whitelist-only + replay protection (sourceTxHash unique)
 *   - bridgeBurn: user burn ตัวเอง → emit event สำหรับ relayer (chain id = uint256)
 *   - setBridge: owner-only
 *   - pause / unpause: owner-only, บล็อก transfer
 *   - totalEverMinted / totalEverBurned tracking
 *   - Ownable2Step ownership transfer
 */
describe("USDT_TPIX", function () {
    // helper: generate unique tx hashes for replay-protection testing
    const txHash = (n) => "0x" + n.toString(16).padStart(64, "0");

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
        it("mints when called by whitelisted relayer", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseUnits("1000", 6); // $1000
            const TX = txHash(1);

            await expect(usdt.connect(relayer).bridgeMint(alice.address, amount, TX))
                .to.emit(usdt, "Minted")
                .withArgs(alice.address, amount, TX);

            expect(await usdt.balanceOf(alice.address)).to.equal(amount);
            expect(await usdt.totalEverMinted()).to.equal(amount);
        });

        it("reverts when called by non-bridge", async function () {
            const { usdt, alice } = await loadFixture(deployFixture);
            await expect(
                usdt.connect(alice).bridgeMint(alice.address, 1000n, txHash(2))
            ).to.be.revertedWith("USDT_TPIX: not a bridge");
        });

        it("reverts on zero recipient", async function () {
            const { usdt, relayer } = await loadFixture(deployFixture);
            await expect(
                usdt.connect(relayer).bridgeMint(ethers.ZeroAddress, 1000n, txHash(3))
            ).to.be.revertedWith("USDT_TPIX: zero recipient");
        });

        it("reverts on zero amount", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await expect(
                usdt.connect(relayer).bridgeMint(alice.address, 0, txHash(4))
            ).to.be.revertedWith("USDT_TPIX: zero amount");
        });

        it("reverts on empty txhash", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await expect(
                usdt.connect(relayer).bridgeMint(alice.address, 100n, ethers.ZeroHash)
            ).to.be.revertedWith("USDT_TPIX: empty txhash");
        });

        it("REPLAY PROTECTION: rejects same sourceTxHash twice", async function () {
            const { usdt, relayer, alice, bob } = await loadFixture(deployFixture);
            const amount = ethers.parseUnits("100", 6);
            const TX = txHash(99);

            await usdt.connect(relayer).bridgeMint(alice.address, amount, TX);
            // ลอง mint ซ้ำด้วย hash เดียวกัน → ต้อง revert
            await expect(
                usdt.connect(relayer).bridgeMint(bob.address, amount, TX)
            ).to.be.revertedWith("USDT_TPIX: txhash replayed");

            // verify processedTxHashes mapping
            expect(await usdt.processedTxHashes(TX)).to.equal(true);
        });

        it("accumulates totalEverMinted across distinct tx hashes", async function () {
            const { usdt, relayer, alice, bob } = await loadFixture(deployFixture);
            const a = ethers.parseUnits("500", 6);
            const b = ethers.parseUnits("300", 6);
            await usdt.connect(relayer).bridgeMint(alice.address, a, txHash(10));
            await usdt.connect(relayer).bridgeMint(bob.address, b, txHash(11));
            expect(await usdt.totalEverMinted()).to.equal(a + b);
        });
    });

    describe("bridgeBurn()", function () {
        it("user burns own balance with uint256 chain id", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseUnits("100", 6);
            await usdt.connect(relayer).bridgeMint(alice.address, amount, txHash(20));

            const targetChainId = 56n; // BSC
            const targetAddress = "0xABC123deadbeef";
            await expect(
                usdt.connect(alice).bridgeBurn(amount, targetChainId, targetAddress)
            )
                .to.emit(usdt, "Burned")
                .withArgs(alice.address, amount, targetChainId, targetAddress);

            expect(await usdt.balanceOf(alice.address)).to.equal(0n);
            expect(await usdt.totalEverBurned()).to.equal(amount);
        });

        it("reverts on zero chain id", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await usdt.connect(relayer).bridgeMint(alice.address, 100n, txHash(21));
            await expect(
                usdt.connect(alice).bridgeBurn(100n, 0, "0xdeadbeef")
            ).to.be.revertedWith("USDT_TPIX: zero chain id");
        });

        it("reverts on empty target address string", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await usdt.connect(relayer).bridgeMint(alice.address, 100n, txHash(22));

            await expect(
                usdt.connect(alice).bridgeBurn(100n, 56, "")
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
            await usdt.connect(relayer).bridgeMint(alice.address, amount, txHash(30));

            await usdt.pause();

            await expect(usdt.connect(alice).transfer(bob.address, 1n))
                .to.be.revertedWithCustomError(usdt, "EnforcedPause");

            await expect(
                usdt.connect(relayer).bridgeMint(bob.address, 1n, txHash(31))
            ).to.be.revertedWithCustomError(usdt, "EnforcedPause");
        });

        it("unpause restores operations", async function () {
            const { usdt, relayer, alice } = await loadFixture(deployFixture);
            await usdt.pause();
            await usdt.unpause();

            await expect(
                usdt.connect(relayer).bridgeMint(alice.address, 1n, txHash(40))
            ).to.not.be.reverted;
        });
    });

    describe("Ownable2Step ownership transfer", function () {
        it("transferOwnership requires acceptOwnership step", async function () {
            const { usdt, owner, alice } = await loadFixture(deployFixture);
            await usdt.connect(owner).transferOwnership(alice.address);
            // ownership ยังไม่เปลี่ยน — ต้อง alice acceptOwnership ก่อน
            expect(await usdt.owner()).to.equal(owner.address);
            expect(await usdt.pendingOwner()).to.equal(alice.address);

            await usdt.connect(alice).acceptOwnership();
            expect(await usdt.owner()).to.equal(alice.address);
        });

        it("non-pending account cannot accept ownership", async function () {
            const { usdt, owner, alice, bob } = await loadFixture(deployFixture);
            await usdt.connect(owner).transferOwnership(alice.address);
            await expect(usdt.connect(bob).acceptOwnership())
                .to.be.revertedWithCustomError(usdt, "OwnableUnauthorizedAccount");
        });
    });
});
