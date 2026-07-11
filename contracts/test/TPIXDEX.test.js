/**
 * TPIX DEX (AMM) tests — Factory + Pair + Router02
 *
 * พิสูจน์ว่า AMM ทำงานจริงครบวงจรบน local hardhat ก่อน deploy mainnet:
 *   - createPair / duplicate guard
 *   - addLiquidityETH (native TPIX + USDT)
 *   - swap native↔token, token↔token, multi-hop ผ่าน WTPIX
 *   - removeLiquidityETH
 *   - fee 0.3% ตามสูตร UniV2
 *   - protocol fee (setFeeTo) mint LP ให้ fee collector
 *   - pairFor fix: อ่าน getPair จาก factory (ไม่ใช่ CREATE2 hash เดิมที่พัง)
 *
 * Developed by Xman Studio
 */

const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

// contract WTPIX มี 2 ตัว (sale + bridge) — ต้องใช้ fully qualified name
const WTPIX_FQN = "src/sale/WTPIX_ERC20.sol:WTPIX";

const DEADLINE = () => Math.floor(Date.now() / 1000) + 3600;

describe("TPIXDEX (AMM)", function () {
    let deployer, alice, bob, feeCollector;
    let wtpix, usdt, factory, router;

    /** mint USDT ให้ address ผ่าน bridge whitelist (deployer เป็น owner) */
    let mintNonce = 0;
    async function mintUsdt(to, amount) {
        await usdt.setBridge(deployer.address, true);
        await usdt.bridgeMint(to, amount, ethers.id(`test-mint-${mintNonce++}`));
        await usdt.setBridge(deployer.address, false);
    }

    // loadFixture: snapshot + revert ทุกเทสต์ — balance native ไม่ไหลข้ามเทสต์
    async function deployDexFixture() {
        const [deployer, alice, bob, feeCollector] = await ethers.getSigners();

        const wtpix = await (await ethers.getContractFactory(WTPIX_FQN)).deploy();
        const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        const factory = await (await ethers.getContractFactory("TPIXDEXFactory")).deploy(deployer.address);
        const router = await (
            await ethers.getContractFactory("TPIXDEXRouter02")
        ).deploy(await factory.getAddress(), await wtpix.getAddress());

        return { deployer, alice, bob, feeCollector, wtpix, usdt, factory, router };
    }

    beforeEach(async function () {
        ({ deployer, alice, bob, feeCollector, wtpix, usdt, factory, router } =
            await loadFixture(deployDexFixture));
    });

    // =====================================================================
    // Factory
    // =====================================================================
    describe("Factory", function () {
        it("createPair สร้าง pair และลง mapping สองทิศทาง", async function () {
            await factory.createPair(await wtpix.getAddress(), await usdt.getAddress());
            const pair = await factory.getPair(await wtpix.getAddress(), await usdt.getAddress());
            expect(pair).to.not.equal(ethers.ZeroAddress);
            expect(await factory.getPair(await usdt.getAddress(), await wtpix.getAddress())).to.equal(pair);
            expect(await factory.allPairsLength()).to.equal(1);
        });

        it("createPair ซ้ำ → revert PAIR_EXISTS", async function () {
            await factory.createPair(await wtpix.getAddress(), await usdt.getAddress());
            await expect(
                factory.createPair(await usdt.getAddress(), await wtpix.getAddress())
            ).to.be.revertedWith("TPIX: PAIR_EXISTS");
        });

        it("token เดียวกัน → revert IDENTICAL_ADDRESSES", async function () {
            await expect(
                factory.createPair(await usdt.getAddress(), await usdt.getAddress())
            ).to.be.revertedWith("TPIX: IDENTICAL_ADDRESSES");
        });

        it("setFeeTo ทำได้เฉพาะ feeToSetter", async function () {
            await expect(
                factory.connect(alice).setFeeTo(alice.address)
            ).to.be.revertedWith("TPIX: FORBIDDEN");
            await factory.setFeeTo(feeCollector.address);
            expect(await factory.feeTo()).to.equal(feeCollector.address);
        });
    });

    // =====================================================================
    // Liquidity
    // =====================================================================
    describe("Liquidity (native TPIX + USDT)", function () {
        const LIQ_TPIX = ethers.parseEther("1000");      // 1,000 TPIX
        const LIQ_USDT = ethers.parseUnits("100", 6);    // 100 USDT → ราคาเปิด 0.10 $/TPIX

        it("addLiquidityETH สร้าง pair อัตโนมัติ + mint LP", async function () {
            await mintUsdt(deployer.address, LIQ_USDT);
            await usdt.approve(await router.getAddress(), LIQ_USDT);

            await router.addLiquidityETH(
                await usdt.getAddress(),
                LIQ_USDT,
                LIQ_USDT,
                LIQ_TPIX,
                deployer.address,
                DEADLINE(),
                { value: LIQ_TPIX }
            );

            const pairAddress = await factory.getPair(await wtpix.getAddress(), await usdt.getAddress());
            expect(pairAddress).to.not.equal(ethers.ZeroAddress);

            const pair = await ethers.getContractAt("TPIXDEXPair", pairAddress);
            const lpBalance = await pair.balanceOf(deployer.address);
            expect(lpBalance).to.be.gt(0);
            // liquidity แรก = sqrt(a*b) - MINIMUM_LIQUIDITY (1000 ถูกล็อกที่ 0xdead)
            expect(await pair.totalSupply()).to.equal(lpBalance + 1000n);

            // reserves ตรงกับที่เติม
            const [r0, r1] = await pair.getReserves();
            const token0 = await pair.token0();
            const [reserveUsdt, reserveWtpix] =
                token0.toLowerCase() === (await usdt.getAddress()).toLowerCase() ? [r0, r1] : [r1, r0];
            expect(reserveUsdt).to.equal(LIQ_USDT);
            expect(reserveWtpix).to.equal(LIQ_TPIX);
        });

        it("removeLiquidityETH คืน token + native ครบ (หัก MINIMUM_LIQUIDITY)", async function () {
            await mintUsdt(deployer.address, LIQ_USDT);
            await usdt.approve(await router.getAddress(), LIQ_USDT);
            await router.addLiquidityETH(
                await usdt.getAddress(), LIQ_USDT, LIQ_USDT, LIQ_TPIX,
                deployer.address, DEADLINE(), { value: LIQ_TPIX }
            );

            const pairAddress = await factory.getPair(await wtpix.getAddress(), await usdt.getAddress());
            const pair = await ethers.getContractAt("TPIXDEXPair", pairAddress);
            const lpBalance = await pair.balanceOf(deployer.address);
            await pair.approve(await router.getAddress(), lpBalance);

            const usdtBefore = await usdt.balanceOf(deployer.address);
            await router.removeLiquidityETH(
                await usdt.getAddress(), lpBalance, 0, 0, deployer.address, DEADLINE()
            );
            const usdtReturned = (await usdt.balanceOf(deployer.address)) - usdtBefore;

            // ได้คืนเกือบทั้งหมด — ขาดเฉพาะสัดส่วนของ MINIMUM_LIQUIDITY ที่ล็อกถาวร
            expect(usdtReturned).to.be.gt((LIQ_USDT * 999n) / 1000n);
        });
    });

    // =====================================================================
    // Swaps
    // =====================================================================
    describe("Swaps", function () {
        const LIQ_TPIX = ethers.parseEther("5000");     // 5,000 TPIX
        const LIQ_USDT = ethers.parseUnits("500", 6);   // 500 USDT → ราคาเปิด 0.10 $/TPIX

        beforeEach(async function () {
            await mintUsdt(deployer.address, LIQ_USDT);
            await usdt.approve(await router.getAddress(), LIQ_USDT);
            await router.addLiquidityETH(
                await usdt.getAddress(), LIQ_USDT, LIQ_USDT, LIQ_TPIX,
                deployer.address, DEADLINE(), { value: LIQ_TPIX }
            );
        });

        it("swapExactETHForTokens: native TPIX → USDT ได้ output ตาม quote", async function () {
            const amountIn = ethers.parseEther("100"); // 100 TPIX
            const path = [await wtpix.getAddress(), await usdt.getAddress()];
            const quoted = await router.getAmountsOut(amountIn, path);

            await router.connect(alice).swapExactETHForTokens(
                quoted[1], path, alice.address, DEADLINE(), { value: amountIn }
            );

            expect(await usdt.balanceOf(alice.address)).to.equal(quoted[1]);
            // fee 0.3%: output < ราคา spot (10 USDT) เสมอ
            expect(quoted[1]).to.be.lt(ethers.parseUnits("10", 6));
        });

        it("swapExactTokensForETH: USDT → native TPIX", async function () {
            const amountIn = ethers.parseUnits("100", 6);
            await mintUsdt(alice.address, amountIn);
            await usdt.connect(alice).approve(await router.getAddress(), amountIn);

            const path = [await usdt.getAddress(), await wtpix.getAddress()];
            const quoted = await router.getAmountsOut(amountIn, path);

            await expect(
                router.connect(alice).swapExactTokensForETH(
                    amountIn, quoted[1], path, alice.address, DEADLINE()
                )
            ).to.changeEtherBalance(alice, quoted[1]);
        });

        it("slippage guard: amountOutMin สูงเกิน → revert", async function () {
            const amountIn = ethers.parseEther("100");
            const path = [await wtpix.getAddress(), await usdt.getAddress()];
            const quoted = await router.getAmountsOut(amountIn, path);

            await expect(
                router.connect(alice).swapExactETHForTokens(
                    quoted[1] + 1n, path, alice.address, DEADLINE(), { value: amountIn }
                )
            ).to.be.revertedWith("TPIX: INSUFFICIENT_OUTPUT_AMOUNT");
        });

        it("deadline หมดอายุ → revert EXPIRED", async function () {
            await expect(
                router.connect(alice).swapExactETHForTokens(
                    0, [await wtpix.getAddress(), await usdt.getAddress()],
                    alice.address, 1, { value: ethers.parseEther("1") }
                )
            ).to.be.revertedWith("TPIX: EXPIRED");
        });

        it("getAmountOut ตรงสูตร UniV2 (fee 0.3%)", async function () {
            const amountIn = ethers.parseEther("100");
            const reserveIn = ethers.parseEther("5000");
            const reserveOut = ethers.parseUnits("500", 6);

            const expected = (amountIn * 997n * reserveOut) / (reserveIn * 1000n + amountIn * 997n);
            expect(await router.getAmountOut(amountIn, reserveIn, reserveOut)).to.equal(expected);
        });

        it("quote บน pair ที่ยังไม่มี → revert PAIR_NOT_FOUND (pairFor fix)", async function () {
            const stray = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
            await expect(
                router.getAmountsOut(ethers.parseEther("1"), [
                    await wtpix.getAddress(),
                    await stray.getAddress(),
                ])
            ).to.be.revertedWith("TPIXDEXLibrary: PAIR_NOT_FOUND");
        });
    });

    // =====================================================================
    // Token ↔ token + multi-hop
    // =====================================================================
    describe("Token↔token + multi-hop", function () {
        let tokenB; // อีก token หนึ่ง (ใช้ USDT_TPIX instance ที่สองแทน mock)

        beforeEach(async function () {
            tokenB = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
            await tokenB.setBridge(deployer.address, true);
            await tokenB.bridgeMint(deployer.address, ethers.parseUnits("50000", 6), ethers.id("seed-b"));
            await tokenB.setBridge(deployer.address, false);

            // pool 1: WTPIX/USDT (0.10 $/TPIX)
            await mintUsdt(deployer.address, ethers.parseUnits("10000", 6));
            await usdt.approve(await router.getAddress(), ethers.parseUnits("10000", 6));
            await router.addLiquidityETH(
                await usdt.getAddress(),
                ethers.parseUnits("10000", 6), 0, 0,
                deployer.address, DEADLINE(),
                { value: ethers.parseEther("2000") }
            );

            // pool 2: WTPIX/tokenB
            await tokenB.approve(await router.getAddress(), ethers.parseUnits("20000", 6));
            await router.addLiquidityETH(
                await tokenB.getAddress(),
                ethers.parseUnits("20000", 6), 0, 0,
                deployer.address, DEADLINE(),
                { value: ethers.parseEther("2000") }
            );
        });

        it("swapExactTokensForTokens: pair ตรง USDT → tokenB (ผ่าน addLiquidity คู่ตรง)", async function () {
            // เติม pool คู่ตรง USDT/tokenB
            await mintUsdt(deployer.address, ethers.parseUnits("5000", 6));
            await tokenB.setBridge(deployer.address, true);
            await tokenB.bridgeMint(deployer.address, ethers.parseUnits("5000", 6), ethers.id("seed-b2"));
            await tokenB.setBridge(deployer.address, false);
            await usdt.approve(await router.getAddress(), ethers.parseUnits("5000", 6));
            await tokenB.approve(await router.getAddress(), ethers.parseUnits("5000", 6));
            await router.addLiquidity(
                await usdt.getAddress(), await tokenB.getAddress(),
                ethers.parseUnits("5000", 6), ethers.parseUnits("5000", 6),
                0, 0, deployer.address, DEADLINE()
            );

            const amountIn = ethers.parseUnits("100", 6);
            await mintUsdt(alice.address, amountIn);
            await usdt.connect(alice).approve(await router.getAddress(), amountIn);

            const path = [await usdt.getAddress(), await tokenB.getAddress()];
            const quoted = await router.getAmountsOut(amountIn, path);
            await router.connect(alice).swapExactTokensForTokens(
                amountIn, quoted[1], path, alice.address, DEADLINE()
            );
            expect(await tokenB.balanceOf(alice.address)).to.equal(quoted[1]);
        });

        it("multi-hop: USDT → WTPIX → tokenB (พิสูจน์ pairFor chaining ใน _swap)", async function () {
            const amountIn = ethers.parseUnits("100", 6);
            await mintUsdt(alice.address, amountIn);
            await usdt.connect(alice).approve(await router.getAddress(), amountIn);

            const path = [
                await usdt.getAddress(),
                await wtpix.getAddress(),
                await tokenB.getAddress(),
            ];
            const quoted = await router.getAmountsOut(amountIn, path);
            expect(quoted[2]).to.be.gt(0);

            await router.connect(alice).swapExactTokensForTokens(
                amountIn, quoted[2], path, alice.address, DEADLINE()
            );
            expect(await tokenB.balanceOf(alice.address)).to.equal(quoted[2]);
        });
    });

    // =====================================================================
    // Protocol fee (กลไกเก็บ fee เข้าแพลตฟอร์ม)
    // =====================================================================
    describe("Protocol fee", function () {
        it("setFeeTo แล้ว swap → fee collector ได้ LP token ตอน liquidity event ถัดไป", async function () {
            await factory.setFeeTo(feeCollector.address);

            // เติม pool
            const LIQ_USDT = ethers.parseUnits("10000", 6);
            await mintUsdt(deployer.address, LIQ_USDT * 2n);
            await usdt.approve(await router.getAddress(), LIQ_USDT * 2n);
            await router.addLiquidityETH(
                await usdt.getAddress(), LIQ_USDT, 0, 0,
                deployer.address, DEADLINE(), { value: ethers.parseEther("5000") }
            );

            const pairAddress = await factory.getPair(await wtpix.getAddress(), await usdt.getAddress());
            const pair = await ethers.getContractAt("TPIXDEXPair", pairAddress);

            // swap หลายรอบให้ k โต (fee สะสมใน pool)
            for (let i = 0; i < 5; i++) {
                await router.connect(alice).swapExactETHForTokens(
                    0, [await wtpix.getAddress(), await usdt.getAddress()],
                    alice.address, DEADLINE(), { value: ethers.parseEther("200") }
                );
                const back = await usdt.balanceOf(alice.address);
                await usdt.connect(alice).approve(await router.getAddress(), back);
                await router.connect(alice).swapExactTokensForETH(
                    back, 0, [await usdt.getAddress(), await wtpix.getAddress()],
                    alice.address, DEADLINE()
                );
            }

            // protocol fee mint ตอน liquidity event ถัดไป (mint/burn)
            expect(await pair.balanceOf(feeCollector.address)).to.equal(0);
            await router.addLiquidityETH(
                await usdt.getAddress(), ethers.parseUnits("100", 6), 0, 0,
                deployer.address, DEADLINE(), { value: ethers.parseEther("1000") }
            );
            expect(await pair.balanceOf(feeCollector.address)).to.be.gt(0);
        });
    });
});
