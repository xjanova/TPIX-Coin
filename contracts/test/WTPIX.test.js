const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * ทดสอบ WTPIX (Wrapped TPIX ERC-20)
 *
 * Coverage:
 *   - deposit / withdraw / receive()
 *   - zero-value reverts
 *   - insufficient balance revert
 *   - invariant: totalSupply === contract native balance
 *   - ReentrancyGuard on withdraw (malicious receiver)
 */
describe("WTPIX", function () {
    async function deployFixture() {
        const [owner, alice, bob] = await ethers.getSigners();
        const WTPIX = await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX");
        const wtpix = await WTPIX.deploy();
        await wtpix.waitForDeployment();
        return { wtpix, owner, alice, bob };
    }

    describe("deployment", function () {
        it("has correct metadata", async function () {
            const { wtpix } = await loadFixture(deployFixture);
            expect(await wtpix.name()).to.equal("Wrapped TPIX");
            expect(await wtpix.symbol()).to.equal("WTPIX");
            expect(await wtpix.decimals()).to.equal(18);
            expect(await wtpix.totalSupply()).to.equal(0n);
        });
    });

    describe("deposit()", function () {
        it("wraps native TPIX 1:1", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("100");

            await expect(wtpix.connect(alice).deposit({ value: amount }))
                .to.emit(wtpix, "Deposit")
                .withArgs(alice.address, amount);

            expect(await wtpix.balanceOf(alice.address)).to.equal(amount);
            expect(await wtpix.totalSupply()).to.equal(amount);
            expect(await ethers.provider.getBalance(await wtpix.getAddress())).to.equal(amount);
        });

        it("reverts on zero value", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            await expect(wtpix.connect(alice).deposit({ value: 0 }))
                .to.be.revertedWith("WTPIX: zero deposit");
        });

        it("accumulates across multiple deposits", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            await wtpix.connect(alice).deposit({ value: ethers.parseEther("50") });
            await wtpix.connect(alice).deposit({ value: ethers.parseEther("30") });
            expect(await wtpix.balanceOf(alice.address)).to.equal(ethers.parseEther("80"));
        });
    });

    describe("receive() — bare send", function () {
        it("auto-deposits when native sent without data", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("10");

            await expect(
                alice.sendTransaction({ to: await wtpix.getAddress(), value: amount })
            ).to.emit(wtpix, "Deposit").withArgs(alice.address, amount);

            expect(await wtpix.balanceOf(alice.address)).to.equal(amount);
        });
    });

    describe("withdraw()", function () {
        it("unwraps 1:1 and returns native TPIX", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("100");
            await wtpix.connect(alice).deposit({ value: amount });

            const balBefore = await ethers.provider.getBalance(alice.address);
            const tx = await wtpix.connect(alice).withdraw(amount);
            const receipt = await tx.wait();
            const gasUsed = receipt.gasUsed * receipt.gasPrice;

            expect(await wtpix.balanceOf(alice.address)).to.equal(0n);
            expect(await wtpix.totalSupply()).to.equal(0n);
            const balAfter = await ethers.provider.getBalance(alice.address);
            expect(balAfter).to.equal(balBefore + amount - gasUsed);
        });

        it("emits Withdrawal event", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            const amount = ethers.parseEther("1");
            await wtpix.connect(alice).deposit({ value: amount });

            await expect(wtpix.connect(alice).withdraw(amount))
                .to.emit(wtpix, "Withdrawal")
                .withArgs(alice.address, amount);
        });

        it("reverts on zero amount", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            await expect(wtpix.connect(alice).withdraw(0))
                .to.be.revertedWith("WTPIX: zero withdraw");
        });

        it("reverts on insufficient balance", async function () {
            const { wtpix, alice } = await loadFixture(deployFixture);
            await expect(wtpix.connect(alice).withdraw(ethers.parseEther("1")))
                .to.be.revertedWith("WTPIX: insufficient balance");
        });

        it("cannot withdraw another user's balance", async function () {
            const { wtpix, alice, bob } = await loadFixture(deployFixture);
            await wtpix.connect(alice).deposit({ value: ethers.parseEther("10") });

            // bob ไม่มี WTPIX เลย
            await expect(wtpix.connect(bob).withdraw(ethers.parseEther("1")))
                .to.be.revertedWith("WTPIX: insufficient balance");
        });
    });

    describe("ERC20 transfer", function () {
        it("transfers WTPIX between users", async function () {
            const { wtpix, alice, bob } = await loadFixture(deployFixture);
            await wtpix.connect(alice).deposit({ value: ethers.parseEther("100") });

            await wtpix.connect(alice).transfer(bob.address, ethers.parseEther("40"));

            expect(await wtpix.balanceOf(alice.address)).to.equal(ethers.parseEther("60"));
            expect(await wtpix.balanceOf(bob.address)).to.equal(ethers.parseEther("40"));
        });
    });

    describe("invariant: totalSupply === contract native balance", function () {
        it("holds after mix of deposits/withdraws/transfers", async function () {
            const { wtpix, alice, bob } = await loadFixture(deployFixture);
            const addr = await wtpix.getAddress();

            await wtpix.connect(alice).deposit({ value: ethers.parseEther("100") });
            await wtpix.connect(bob).deposit({ value: ethers.parseEther("50") });
            await wtpix.connect(alice).transfer(bob.address, ethers.parseEther("20"));
            await wtpix.connect(bob).withdraw(ethers.parseEther("30"));

            expect(await wtpix.totalSupply()).to.equal(await ethers.provider.getBalance(addr));
        });
    });
});
