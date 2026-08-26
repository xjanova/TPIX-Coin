/**
 * TPIX Token Factory — สร้างเหรียญได้จริงทุกประเภท ทุกออฟชั่น
 *
 * ทำไมต้องมีไฟล์นี้:
 * สัญญาชุด token-factory เคยอยู่ที่ contracts/token-factory/ ซึ่งอยู่นอก paths.sources
 * ของ hardhat (./src) → **ไม่เคยถูกคอมไพล์เลยสักครั้ง** จึงไม่เคยมีเทสต์ ไม่เคยมีใครรู้ว่า
 * มันทำงานไหม ทั้งที่หน้าเว็บ /token-factory เปิดให้คนกดสร้างเหรียญมาตลอด
 *
 * เทสต์ชุดนี้ยืนยัน 2 อย่าง:
 *   1. ทุก create*() บนแฟกทอรีสร้างสัญญาที่มีโค้ดจริงบนเชน ไม่ใช่ address เปล่า
 *   2. ทุกออฟชั่นที่หน้าเว็บให้ติ๊กได้ ส่งผลกับพฤติกรรมของเหรียญจริง ไม่ใช่ธงที่ไม่มีใครอ่าน
 *      (ติ๊ก mintable แล้ว mint ต้องได้ · ไม่ติ๊กแล้ว mint ต้องโดนปฏิเสธ)
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const E18 = 10n ** 18n;
const SUPPLY = 1_000_000n * E18;

describe("TPIX Token Factory", function () {
    let owner, user, other, taxWallet, marketingWallet, reserveWallet;
    let tokenFactory, nftFactory;

    /** ดึง address ของเหรียญที่เพิ่งสร้างออกมาจาก event ไม่ใช่เดาจาก return ของ tx */
    async function createdAddress(tx, factory) {
        const receipt = await tx.wait();
        const log = receipt.logs
            .map((l) => { try { return factory.interface.parseLog(l); } catch { return null; } })
            .find((l) => l && (l.name === "TokenCreated" || l.name === "NFTCreated"));
        expect(log, "ต้องมี event ตอนสร้างเหรียญ").to.not.equal(undefined);
        return log.args[0];
    }

    /** เหรียญที่สร้างต้องมีโค้ดอยู่บนเชนจริง — address เปล่าถือว่าล้มเหลว */
    async function expectLiveContract(addr) {
        expect(addr).to.properAddress;
        expect(await ethers.provider.getCode(addr)).to.not.equal("0x");
    }

    beforeEach(async function () {
        [owner, user, other, taxWallet, marketingWallet, reserveWallet] = await ethers.getSigners();

        const creators = {};
        for (const n of [
            "ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator",
            "GovernanceTokenCreator", "StablecoinTokenCreator",
            "FactoryERC721Creator", "NFTCollectionCreator",
        ]) {
            const C = await ethers.getContractFactory(n);
            const c = await C.deploy();
            await c.waitForDeployment();
            creators[n] = await c.getAddress();
        }

        const TF = await ethers.getContractFactory("TPIXTokenFactoryV2");
        tokenFactory = await TF.deploy(
            creators.ERC20V2Creator, creators.UtilityTokenCreator, creators.RewardTokenCreator,
            creators.GovernanceTokenCreator, creators.StablecoinTokenCreator
        );
        await tokenFactory.waitForDeployment();

        const NF = await ethers.getContractFactory("TPIXNFTFactory");
        nftFactory = await NF.deploy(creators.FactoryERC721Creator, creators.NFTCollectionCreator);
        await nftFactory.waitForDeployment();
    });

    // ═══════════════════════════════════════════════════════════
    //  ERC-20 มาตรฐาน (standard / mintable / burnable)
    // ═══════════════════════════════════════════════════════════
    describe("ERC-20 มาตรฐาน", function () {
        async function makeERC20(opts = {}) {
            const o = {
                mintable: false, burnable: false, pausable: false, blacklist: false,
                mintCap: 0, autoBurn: false, autoBurnBps: 0, burnFloor: 0,
                decimals: 18, supply: SUPPLY, ...opts,
            };
            const tx = await tokenFactory.createERC20V2(
                "Test Token", "TEST", o.decimals, o.supply, user.address,
                o.mintable, o.burnable, o.pausable, o.blacklist,
                o.mintCap, o.autoBurn, o.autoBurnBps, o.burnFloor
            );
            const addr = await createdAddress(tx, tokenFactory);
            await expectLiveContract(addr);
            return ethers.getContractAt("FactoryERC20V2", addr);
        }

        it("สร้างแล้วซัพพลายทั้งก้อนไปอยู่กับกระเป๋าผู้ใช้ ไม่ใช่กระเป๋าเซิร์ฟเวอร์", async function () {
            const t = await makeERC20();
            expect(await t.name()).to.equal("Test Token");
            expect(await t.symbol()).to.equal("TEST");
            expect(await t.totalSupply()).to.equal(SUPPLY);
            expect(await t.balanceOf(user.address)).to.equal(SUPPLY);
            expect(await t.balanceOf(owner.address)).to.equal(0n);
            expect(await t.owner()).to.equal(user.address);
        });

        it("ทศนิยมที่ไม่ใช่ 18 ก็ต้องได้ตามที่สั่ง", async function () {
            const t = await makeERC20({ decimals: 6, supply: 1_000_000n * 10n ** 6n });
            expect(await t.decimals()).to.equal(6);
            expect(await t.totalSupply()).to.equal(1_000_000n * 10n ** 6n);
        });

        it("ไม่ติ๊ก mintable = mint ไม่ได้ · ติ๊กแล้ว = เจ้าของ mint ได้", async function () {
            const off = await makeERC20({ mintable: false });
            await expect(off.connect(user).mint(user.address, E18)).to.be.reverted;

            const on = await makeERC20({ mintable: true });
            await on.connect(user).mint(other.address, 5n * E18);
            expect(await on.balanceOf(other.address)).to.equal(5n * E18);
        });

        it("mintCap กันไม่ให้ปั๊มเกินเพดานที่ตั้งไว้", async function () {
            const cap = SUPPLY + 100n * E18;
            const t = await makeERC20({ mintable: true, mintCap: cap });
            expect(await t.mintCap()).to.equal(cap);

            await t.connect(user).mint(user.address, 100n * E18);
            await expect(t.connect(user).mint(user.address, 1n * E18)).to.be.reverted;
        });

        it("ไม่ติ๊ก burnable = เผาไม่ได้ · ติ๊กแล้ว = เผาแล้วซัพพลายลดจริง", async function () {
            const off = await makeERC20({ burnable: false });
            await expect(off.connect(user).burn(E18)).to.be.reverted;

            const on = await makeERC20({ burnable: true });
            await on.connect(user).burn(1000n * E18);
            expect(await on.totalSupply()).to.equal(SUPPLY - 1000n * E18);
        });

        it("pausable หยุดการโอนได้จริงและปลดกลับมาได้", async function () {
            const t = await makeERC20({ pausable: true });
            await t.connect(user).pause();
            expect(await t.paused()).to.equal(true);
            await expect(t.connect(user).transfer(other.address, E18)).to.be.reverted;

            await t.connect(user).unpause();
            await t.connect(user).transfer(other.address, E18);
            expect(await t.balanceOf(other.address)).to.equal(E18);
        });

        it("ไม่ติ๊ก pausable = ปุ่ม pause ใช้ไม่ได้ (ไม่ใช่ธงลอย ๆ)", async function () {
            const t = await makeERC20({ pausable: false });
            await expect(t.connect(user).pause()).to.be.reverted;
        });

        it("blacklist บล็อกกระเป๋าที่ถูกขึ้นบัญชีได้จริง", async function () {
            const t = await makeERC20({ blacklist: true });
            await t.connect(user).transfer(other.address, 10n * E18);

            await t.connect(user).setBlacklist(other.address, true);
            expect(await t.blacklisted(other.address)).to.equal(true);
            await expect(t.connect(other).transfer(user.address, E18)).to.be.reverted;

            await t.connect(user).setBlacklist(other.address, false);
            await t.connect(other).transfer(user.address, E18);
        });

        it("auto-burn เผาทุกครั้งที่โอน จนกว่าจะถึงพื้นที่ตั้งไว้", async function () {
            const floor = SUPPLY - 5000n * E18;
            const t = await makeERC20({ autoBurn: true, autoBurnBps: 100, burnFloor: floor }); // 1%
            expect(await t.isAutoBurnEnabled()).to.equal(true);
            expect(await t.autoBurnRateBps()).to.equal(100);
            expect(await t.burnFloor()).to.equal(floor);

            await t.connect(user).transfer(other.address, 1000n * E18);

            const burned = SUPPLY - (await t.totalSupply());
            expect(burned).to.equal(10n * E18);                       // 1% ของ 1000
            expect(await t.balanceOf(other.address)).to.equal(990n * E18); // ผู้รับได้ยอดหลังหักเผา
        });

        it("แฟกทอรีจดทะเบียนเหรียญที่สร้างไว้ให้ตรวจย้อนหลังได้", async function () {
            const t = await makeERC20();
            const addr = await t.getAddress();

            expect(await tokenFactory.totalTokens()).to.equal(1n);
            expect(await tokenFactory.getToken(0)).to.equal(addr);

            const rec = await tokenFactory.tokenRecords(addr);
            expect(rec.symbol).to.equal("TEST");
            expect(rec.tokenOwner).to.equal(user.address);
            expect(rec.category).to.equal(0);
        });

        it("คนนอกเรียกแฟกทอรีสร้างเหรียญเองไม่ได้ (onlyOwner)", async function () {
            await expect(
                tokenFactory.connect(other).createERC20V2(
                    "Hack", "HACK", 18, SUPPLY, other.address,
                    false, false, false, false, 0, false, 0, 0
                )
            ).to.be.reverted;
        });

        it("สร้างหลายใบติดกันได้ ไม่ชนกันเอง (salt ต้องไม่ซ้ำ)", async function () {
            const a = await makeERC20();
            const b = await makeERC20();
            expect(await a.getAddress()).to.not.equal(await b.getAddress());
            expect(await tokenFactory.totalTokens()).to.equal(2n);
        });
    });

    // ═══════════════════════════════════════════════════════════
    //  Utility Token — ภาษี + กันปลาวาฬ + กันบอท
    // ═══════════════════════════════════════════════════════════
    describe("Utility Token", function () {
        async function makeUtility(tax = {}, prot = {}) {
            const taxConfig = {
                buyTaxBps: 0, sellTaxBps: 0, transferTaxBps: 0,
                taxWallet: taxWallet.address, marketingWallet: marketingWallet.address,
                marketingShareBps: 0, ...tax,
            };
            const protectionConfig = {
                maxWalletBps: 0, maxTxBps: 0, antiBotDuration: 0, tradingCooldown: 0, ...prot,
            };
            const tx = await tokenFactory.createUtilityToken(
                "Utility", "UTIL", 18, SUPPLY, user.address,
                true, true, true, true, taxConfig, protectionConfig
            );
            const addr = await createdAddress(tx, tokenFactory);
            await expectLiveContract(addr);
            return ethers.getContractAt("UtilityToken", addr);
        }

        it("ตั้งค่าภาษีแล้วอ่านกลับมาได้ตรง", async function () {
            const t = await makeUtility({ buyTaxBps: 300, sellTaxBps: 500, transferTaxBps: 100, marketingShareBps: 4000 });
            expect(await t.buyTaxBps()).to.equal(300);
            expect(await t.sellTaxBps()).to.equal(500);
            expect(await t.transferTaxBps()).to.equal(100);
            expect(await t.taxEnabled()).to.equal(true);
            expect(await t.taxWallet()).to.equal(taxWallet.address);
            expect(await t.marketingWallet()).to.equal(marketingWallet.address);
            expect(await t.marketingShareBps()).to.equal(4000);
        });

        it("ภาษีโอนหักจริง แล้วเข้ากระเป๋าภาษี/การตลาดตามสัดส่วน", async function () {
            const t = await makeUtility({ transferTaxBps: 1000, marketingShareBps: 3000 }); // ภาษี 10% แบ่งการตลาด 30%
            await t.connect(user).enableTrading();

            // constructor ตั้ง isExcluded[owner] = true ให้เอง เจ้าของจึงไม่โดนภาษี
            // ต้องส่งต่อไปกระเป๋าที่ไม่ถูกยกเว้นก่อน แล้วค่อยวัดตอนกระเป๋านั้นโอนออก
            await t.connect(user).transfer(other.address, 2000n * E18);
            expect(await t.balanceOf(other.address)).to.equal(2000n * E18);

            await t.connect(other).transfer(owner.address, 1000n * E18);
            expect(await t.balanceOf(owner.address)).to.equal(900n * E18);
            const collected = (await t.balanceOf(taxWallet.address)) + (await t.balanceOf(marketingWallet.address));
            expect(collected).to.equal(100n * E18);
            expect(await t.balanceOf(marketingWallet.address)).to.equal(30n * E18);
        });

        it("กระเป๋าที่ถูกยกเว้นไม่โดนหักภาษี", async function () {
            const t = await makeUtility({ transferTaxBps: 1000 });
            await t.connect(user).enableTrading();
            await t.connect(user).setExcluded(other.address, true);
            expect(await t.isExcluded(other.address)).to.equal(true);

            // other ถูกยกเว้นแล้ว โอนออกจาก other ก็ต้องไม่โดนหัก
            await t.connect(user).transfer(other.address, 1000n * E18);
            await t.connect(other).transfer(owner.address, 1000n * E18);
            expect(await t.balanceOf(owner.address)).to.equal(1000n * E18);
        });

        it("กันปลาวาฬ: ถือเกินเพดานต่อกระเป๋าไม่ได้", async function () {
            const t = await makeUtility({}, { maxWalletBps: 100 }); // 1% ของซัพพลาย
            await t.connect(user).enableTrading();
            expect(await t.antiWhaleEnabled()).to.equal(true);
            expect(await t.maxWalletAmount()).to.equal(SUPPLY / 100n);

            // constructor ยกเว้น owner + taxWallet + marketingWallet ทั้งสามตัว
            // ผู้โอนจึงต้องเป็นกระเป๋าที่ไม่อยู่ในรายการนั้น (ที่นี่ใช้ owner ของ hardhat)
            await t.connect(user).transfer(other.address, SUPPLY / 100n);
            await t.connect(user).transfer(owner.address, 10n * E18);
            await expect(t.connect(owner).transfer(other.address, E18)).to.be.reverted;
        });

        it("กันปลาวาฬ: โอนต่อครั้งเกินเพดานไม่ได้", async function () {
            const t = await makeUtility({}, { maxTxBps: 50 }); // 0.5%
            await t.connect(user).enableTrading();
            expect(await t.maxTxAmount()).to.equal((SUPPLY * 50n) / 10000n);

            await t.connect(user).transfer(other.address, (SUPPLY * 200n) / 10000n); // เจ้าของยกเว้น
            await expect(t.connect(other).transfer(owner.address, (SUPPLY * 51n) / 10000n)).to.be.reverted;
            await t.connect(other).transfer(owner.address, (SUPPLY * 50n) / 10000n);
        });

        it("ยังไม่เปิดเทรด = คนทั่วไปโอนไม่ได้ (กันบอทซื้อก่อนเปิด)", async function () {
            const t = await makeUtility({}, { antiBotDuration: 60 });
            expect(await t.tradingEnabled()).to.equal(false);
            expect(await t.antiBotEnabled()).to.equal(true);

            // เจ้าของยังแจกจ่ายก่อนเปิดได้ (ถูกยกเว้น)
            await t.connect(user).transfer(other.address, 100n * E18);
            // แต่คนทั่วไปโอนกันเองไม่ได้จนกว่าจะเปิดเทรด
            await expect(t.connect(other).transfer(owner.address, E18))
                .to.be.revertedWith("UT: trading not enabled");

            await t.connect(user).enableTrading();
            expect(await t.tradingEnabled()).to.equal(true);
            await t.connect(other).transfer(owner.address, E18);
        });

        it("คูลดาวน์: กระเป๋าเดิมโอนซ้ำเร็วเกินไปไม่ได้", async function () {
            // คูลดาวน์บังคับเฉพาะในช่วงกันบอทหลังเปิดเทรด (launchTime .. +antiBotDuration)
            // ตั้ง cooldown อย่างเดียวโดยไม่ตั้งช่วงกันบอท = ด่านนี้ไม่มีวันทำงาน
            const t = await makeUtility({}, { tradingCooldown: 300, antiBotDuration: 3600 });
            expect(await t.tradingCooldown()).to.equal(300);

            await t.connect(user).transfer(other.address, 100n * E18);
            await t.connect(user).enableTrading();

            await t.connect(other).transfer(owner.address, E18);
            await expect(t.connect(other).transfer(owner.address, E18))
                .to.be.revertedWith("UT: cooldown active");

            await time.increase(301);
            await t.connect(other).transfer(owner.address, E18);
        });
    });

    // ═══════════════════════════════════════════════════════════
    //  Reward Token — reflection / dividend / vesting
    // ═══════════════════════════════════════════════════════════
    describe("Reward Token", function () {
        async function makeReward(rewardType, rateBps = 500, minHold = 0, cliff = 0, duration = 0) {
            const tx = await tokenFactory.createRewardToken(
                "Reward", "RWD", 18, SUPPLY, user.address,
                true, true, true, true,
                rewardType, rateBps, minHold, cliff, duration
            );
            const addr = await createdAddress(tx, tokenFactory);
            await expectLiveContract(addr);
            return ethers.getContractAt("RewardToken", addr);
        }

        it("บันทึกชนิดรางวัลและอัตราไว้ถูกต้อง", async function () {
            const t = await makeReward(0, 250, 100n * E18);
            expect(await t.rewardType()).to.equal(0);
            expect(await t.rewardRateBps()).to.equal(250);
            expect(await t.minHoldForReward()).to.equal(100n * E18);
        });

        it("reflection: หักค่าธรรมเนียมทุกการโอนแล้วสะสมไว้จริง", async function () {
            const t = await makeReward(0, 500); // 5%

            // constructor ยกเว้นค่าธรรมเนียมให้เจ้าของ ต้องวัดตอนกระเป๋าธรรมดาโอน
            await t.connect(user).transfer(other.address, 2000n * E18);
            expect(await t.balanceOf(other.address)).to.equal(2000n * E18);

            await t.connect(other).transfer(owner.address, 1000n * E18);
            expect(await t.balanceOf(owner.address)).to.equal(950n * E18);
            expect(await t.balanceOf(other.address)).to.equal(1000n * E18);
            expect(await t.totalReflectionFees()).to.equal(50n * E18);

            // reflection ทำงานด้วยการเผา — ซัพพลายต้องลดลงเท่ากับค่าธรรมเนียม
            expect(await t.totalSupply()).to.equal(SUPPLY - 50n * E18);
        });

        it("กระเป๋าที่ยกเว้นค่าธรรมเนียม โอนแล้วได้เต็ม", async function () {
            const t = await makeReward(0, 500);
            await t.connect(user).setExcludedFromFee(other.address, true);
            expect(await t.isExcludedFromFee(other.address)).to.equal(true);

            await t.connect(user).transfer(other.address, 1000n * E18);
            await t.connect(other).transfer(owner.address, 1000n * E18);
            expect(await t.balanceOf(owner.address)).to.equal(1000n * E18);
        });

        it("vesting: ล็อกไว้ก่อน cliff แล้วทยอยปลดตามเวลา", async function () {
            const cliff = 30 * 86400;
            const duration = 90 * 86400;
            const t = await makeReward(2, 0, 0, cliff, duration);
            expect(await t.vestingCliff()).to.equal(cliff);
            expect(await t.vestingDuration()).to.equal(duration);

            const locked = 1000n * E18;
            await t.connect(user).createVesting(other.address, locked);
            expect(await t.lockedAmountOf(other.address)).to.equal(locked);
            expect(await t.releasableAmountOf(other.address)).to.equal(0n);

            await time.increase(cliff + 1);
            expect(await t.releasableAmountOf(other.address)).to.be.greaterThan(0n);

            await time.increase(duration);
            expect(await t.releasableAmountOf(other.address)).to.equal(locked);

            await t.connect(other).releaseVested();
            expect(await t.balanceOf(other.address)).to.equal(locked);
            expect(await t.lockedAmountOf(other.address)).to.equal(0n);
        });
    });

    // ═══════════════════════════════════════════════════════════
    //  Governance Token — โหวต + มอบสิทธิ์ + permit
    // ═══════════════════════════════════════════════════════════
    describe("Governance Token", function () {
        async function makeGov(delegation = true, mintCap = 0, threshold = 0, quorum = 0, period = 0) {
            const tx = await tokenFactory.createGovernanceToken(
                "Gov", "GOV", 18, SUPPLY, user.address,
                true, true, true, true, delegation,
                mintCap, threshold, quorum, period
            );
            const addr = await createdAddress(tx, tokenFactory);
            await expectLiveContract(addr);
            return ethers.getContractAt("GovernanceToken", addr);
        }

        it("เก็บพารามิเตอร์ธรรมาภิบาลไว้ครบ", async function () {
            const t = await makeGov(true, 0, 1000n * E18, 2000, 7 * 86400);
            expect(await t.isDelegationEnabled()).to.equal(true);
            expect(await t.proposalThreshold()).to.equal(1000n * E18);
            expect(await t.quorumBps()).to.equal(2000);
            expect(await t.votingPeriod()).to.equal(7 * 86400);
        });

        it("มอบสิทธิ์โหวตแล้วคะแนนย้ายไปจริง", async function () {
            const t = await makeGov(true);
            // constructor เรียก _delegate(owner, owner) ให้แล้ว เจ้าของจึงมีคะแนนตั้งแต่แรก
            // ไม่ต้องให้ผู้ใช้มางมว่าทำไมถือเหรียญแล้วโหวตไม่ได้
            expect(await t.getVotes(user.address)).to.equal(SUPPLY);
            expect(await t.delegates(user.address)).to.equal(user.address);
            await t.connect(user).delegate(other.address);
            expect(await t.getVotes(other.address)).to.equal(SUPPLY);
            expect(await t.getVotes(user.address)).to.equal(0n);
        });

        it("ปิดการมอบสิทธิ์ = delegate ไม่ได้", async function () {
            const t = await makeGov(false);
            expect(await t.isDelegationEnabled()).to.equal(false);
            await expect(t.connect(user).delegate(user.address)).to.be.reverted;
        });

        it("อ่านคะแนนย้อนหลังได้ (ใช้ตอนนับโหวต)", async function () {
            const t = await makeGov(true);
            await t.connect(user).delegate(user.address);
            const mark = await time.latestBlock();
            await ethers.provider.send("evm_mine", []);

            await t.connect(user).transfer(other.address, SUPPLY / 2n);
            await ethers.provider.send("evm_mine", []);

            expect(await t.getPastVotes(user.address, mark)).to.equal(SUPPLY);
            expect(await t.getVotes(user.address)).to.equal(SUPPLY / 2n);
        });

        it("มี permit (EIP-2612) ให้อนุมัติด้วยลายเซ็นโดยไม่ต้องจ่ายแก๊ส", async function () {
            const t = await makeGov(true);
            expect(await t.nonces(user.address)).to.equal(0n);
            expect(await t.DOMAIN_SEPARATOR()).to.not.equal(ethers.ZeroHash);
        });

        it("เจ้าของแก้พารามิเตอร์ธรรมาภิบาลทีหลังได้ คนอื่นแก้ไม่ได้", async function () {
            const t = await makeGov(true);
            await t.connect(user).setGovernanceParams(500n * E18, 3000, 5 * 86400);
            expect(await t.quorumBps()).to.equal(3000);

            await expect(t.connect(other).setGovernanceParams(1n, 1, 1)).to.be.reverted;
        });
    });

    // ═══════════════════════════════════════════════════════════
    //  Stablecoin — แช่แข็ง + KYC + ผู้มีสิทธิ์ mint
    // ═══════════════════════════════════════════════════════════
    describe("Stablecoin", function () {
        async function makeStable(freeze = true, kyc = false, pausable = true) {
            const tx = await tokenFactory.createStablecoinToken(
                "Thai Baht Stable", "THBS", 6, 1_000_000n * 10n ** 6n, user.address,
                reserveWallet.address, pausable, freeze, kyc
            );
            const addr = await createdAddress(tx, tokenFactory);
            await expectLiveContract(addr);
            return ethers.getContractAt("StablecoinToken", addr);
        }

        it("สร้างด้วยทศนิยม 6 และผูกกระเป๋าสำรองไว้", async function () {
            const t = await makeStable();
            expect(await t.decimals()).to.equal(6);
            expect(await t.reserveWallet()).to.equal(reserveWallet.address);
            expect(await t.balanceOf(user.address)).to.equal(1_000_000n * 10n ** 6n);
        });

        it("แช่แข็งกระเป๋าได้ แล้วปลดได้", async function () {
            const t = await makeStable(true);
            expect(await t.isFreezeEnabled()).to.equal(true);
            await t.connect(user).transfer(other.address, 100n * 10n ** 6n);

            await t.connect(user).setFrozen(other.address, true);
            expect(await t.frozen(other.address)).to.equal(true);
            await expect(t.connect(other).transfer(user.address, 1n)).to.be.reverted;

            await t.connect(user).setFrozen(other.address, false);
            await t.connect(other).transfer(user.address, 1n);
        });

        it("บังคับ KYC = กระเป๋าที่ยังไม่ผ่านรับเหรียญไม่ได้", async function () {
            const t = await makeStable(true, true);
            expect(await t.isKycRequired()).to.equal(true);

            await expect(t.connect(user).transfer(other.address, 1n)).to.be.reverted;

            await t.connect(user).setKyc(other.address, true);
            await t.connect(user).setKyc(user.address, true);
            expect(await t.kycApproved(other.address)).to.equal(true);
            await t.connect(user).transfer(other.address, 100n);
            expect(await t.balanceOf(other.address)).to.equal(100n);
        });

        it("ตั้งผู้มีสิทธิ์ mint เพิ่มได้ คนที่ไม่ได้รับสิทธิ์ mint ไม่ได้", async function () {
            const t = await makeStable();
            // mint ของ stablecoin บังคับให้ระบุเหตุผลด้วย เพื่อให้ตรวจสอบย้อนหลังได้
            await expect(t.connect(other).mint(other.address, 100n, "test")).to.be.reverted;

            await t.connect(user).setMinter(other.address, true);
            expect(await t.isMinter(other.address)).to.equal(true);
            await t.connect(other).mint(other.address, 100n, "reserve topup");
            expect(await t.balanceOf(other.address)).to.equal(100n);
        });
    });

    // ═══════════════════════════════════════════════════════════
    //  NFT เดี่ยว — soulbound + ค่าลิขสิทธิ์
    // ═══════════════════════════════════════════════════════════
    describe("NFT (ERC-721)", function () {
        async function makeNFT(opts = {}) {
            const o = {
                maxSupply: 100, mintable: true, soulbound: false,
                royalty: false, royaltyBps: 0, ...opts,
            };
            const tx = await nftFactory.createNFT(
                "My NFT", "MNFT", user.address, "ipfs://meta/", o.maxSupply,
                o.mintable, o.soulbound, o.royalty, user.address, o.royaltyBps
            );
            const addr = await createdAddress(tx, nftFactory);
            await expectLiveContract(addr);
            return ethers.getContractAt("FactoryERC721", addr);
        }

        it("สร้าง NFT แล้ว mint ได้ ผู้ถือคือคนที่ระบุ", async function () {
            const n = await makeNFT();
            // createNFT() mint ใบแรกให้เจ้าของทันทีด้วย tokenURI ที่ส่งมาตอนสร้าง
            expect(await n.ownerOf(1)).to.equal(user.address);
            expect(await n.totalMinted()).to.equal(1n);

            await n.connect(user).mint(other.address, "ipfs://meta/2.json");
            expect(await n.ownerOf(2)).to.equal(other.address);
            expect(await n.totalMinted()).to.equal(2n);
        });

        it("เพดานจำนวนใบกันไม่ให้ mint เกิน", async function () {
            const n = await makeNFT({ maxSupply: 2 }); // ใบที่ 1 ถูก mint ตอนสร้างไปแล้ว
            expect(await n.totalMinted()).to.equal(1n);
            await n.connect(user).mint(user.address, "ipfs://2.json");
            await expect(n.connect(user).mint(user.address, "ipfs://3.json"))
                .to.be.revertedWith("NFT: max supply reached");
        });

        it("soulbound = mint ได้แต่โอนต่อไม่ได้", async function () {
            const n = await makeNFT({ soulbound: true });
            expect(await n.isSoulbound()).to.equal(true);
            await n.connect(user).mint(other.address, "ipfs://2.json");
            await expect(
                n.connect(other).transferFrom(other.address, user.address, 2)
            ).to.be.reverted;
        });

        it("ค่าลิขสิทธิ์ตอบตามมาตรฐาน ERC-2981", async function () {
            const n = await makeNFT({ royalty: true, royaltyBps: 750 }); // 7.5%
            expect(await n.isRoyaltyEnabled()).to.equal(true);

            const [receiver, amount] = await n.royaltyInfo(1, 1000n * E18);
            expect(receiver).to.equal(user.address);
            expect(amount).to.equal((1000n * E18 * 750n) / 10000n);
        });
    });

    // ═══════════════════════════════════════════════════════════
    //  NFT Collection — ขายเป็นชุด + เปิดเผยภายหลัง + ไวต์ลิสต์
    // ═══════════════════════════════════════════════════════════
    describe("NFT Collection", function () {
        async function makeCollection(opts = {}) {
            const o = {
                maxSupply: 100, mintType: 0, mintPrice: 0,
                maxPerWallet: 5, maxPerTx: 2, reserveCount: 0,
                baseURI: "ipfs://base/", placeholderURI: "ipfs://hidden.json",
                delayedReveal: false, royalty: false, royaltyBps: 0, ...opts,
            };
            const tx = await nftFactory.createNFTCollection(
                "Collection", "COLL", user.address, o.maxSupply, o.mintType, o.mintPrice,
                o.maxPerWallet, o.maxPerTx, o.reserveCount,
                o.baseURI, o.placeholderURI, o.delayedReveal,
                o.royalty, user.address, o.royaltyBps
            );
            const addr = await createdAddress(tx, nftFactory);
            await expectLiveContract(addr);
            return ethers.getContractAt("NFTCollection", addr);
        }

        it("เก็บค่าคอนฟิกของคอลเลกชันไว้ครบ", async function () {
            const c = await makeCollection({ maxSupply: 50, maxPerWallet: 3, maxPerTx: 2 });
            expect(await c.maxSupply()).to.equal(50n);
            expect(await c.maxPerWallet()).to.equal(3);
            expect(await c.maxPerTx()).to.equal(2);
            expect(await c.remainingSupply()).to.equal(50n);
        });

        it("จำนวนสำรองถูก mint ให้เจ้าของตั้งแต่สร้าง", async function () {
            const c = await makeCollection({ reserveCount: 5 });
            expect(await c.mintedCount(user.address)).to.be.greaterThanOrEqual(0n);
            expect(await c.currentTokenId()).to.equal(5n);
            expect(await c.ownerOf(1)).to.equal(user.address);
        });

        it("ต้องเปิดขายก่อนถึง mint ได้", async function () {
            const c = await makeCollection();
            expect(await c.mintingActive()).to.equal(false);
            await expect(c.connect(other).mint(1)).to.be.reverted;

            await c.connect(user).toggleMinting();
            await c.connect(other).mint(1);
            expect(await c.ownerOf(1)).to.equal(other.address);
        });

        it("เพดานต่อครั้งและต่อกระเป๋าบังคับใช้จริง", async function () {
            const c = await makeCollection({ maxPerTx: 2, maxPerWallet: 3 });
            await c.connect(user).toggleMinting();

            await expect(c.connect(other).mint(3)).to.be.reverted;   // เกินต่อครั้ง
            await c.connect(other).mint(2);
            await c.connect(other).mint(1);
            await expect(c.connect(other).mint(1)).to.be.reverted;   // เกินต่อกระเป๋า
        });

        it("ขายแบบมีราคา: จ่ายไม่ครบ mint ไม่ได้ · เจ้าของถอนเงินได้", async function () {
            const price = E18 / 10n;
            const c = await makeCollection({ mintPrice: price, mintType: 0 }); // 0 = ขายทั่วไป (1 คือไวต์ลิสต์)
            await c.connect(user).toggleMinting();

            await expect(c.connect(other).mint(1, { value: price - 1n })).to.be.reverted;
            await c.connect(other).mint(2, { value: price * 2n });

            const before = await ethers.provider.getBalance(user.address);
            await c.connect(user).withdraw();
            expect(await ethers.provider.getBalance(user.address)).to.be.greaterThan(before);
        });

        it("ไวต์ลิสต์: เฉพาะคนในลิสต์เท่านั้นที่ mint ได้", async function () {
            const c = await makeCollection({ mintType: 1 }); // 1 = ไวต์ลิสต์ (2 = แจกฟรี)
            await c.connect(user).toggleMinting();

            await expect(c.connect(other).mint(1)).to.be.reverted;
            await c.connect(user).setWhitelist([other.address], true);
            expect(await c.whitelisted(other.address)).to.equal(true);
            await c.connect(other).mint(1);
        });

        it("เปิดเผยภายหลัง: ก่อนเปิดทุกใบชี้รูปปิดบัง เปิดแล้วชี้ metadata จริง", async function () {
            const c = await makeCollection({ delayedReveal: true, reserveCount: 1 });
            expect(await c.isDelayedReveal()).to.equal(true);
            expect(await c.revealed()).to.equal(false);
            expect(await c.tokenURI(1)).to.equal("ipfs://hidden.json");

            await c.connect(user).reveal("ipfs://base/");
            expect(await c.revealed()).to.equal(true);
            expect(await c.tokenURI(1)).to.equal("ipfs://base/1.json");
        });

        it("ค่าลิขสิทธิ์ของคอลเลกชันตอบตาม ERC-2981", async function () {
            const c = await makeCollection({ royalty: true, royaltyBps: 500 });
            const [receiver, amount] = await c.royaltyInfo(1, 200n * E18);
            expect(receiver).to.equal(user.address);
            expect(amount).to.equal((200n * E18 * 500n) / 10000n);
        });

        it("คนนอกเรียก NFT factory สร้างเองไม่ได้", async function () {
            await expect(
                nftFactory.connect(other).createNFT(
                    "X", "X", other.address, "ipfs://x", 1, true, false, false, other.address, 0
                )
            ).to.be.reverted;
        });
    });
});
