/**
 * TPIX Token Factory — ด่านความปลอดภัยที่เพิ่มหลังออดิท 2026-10-11
 *
 * แต่ละ describe คือช่องโหว่หนึ่งข้อที่ยืนยันด้วย PoC แล้ว — เทสต์นี้กันมันกลับมา
 *   1. creator ถูกเรียกตรงได้ (ข้ามด่าน factory + ตัดหน้า CREATE2 ทำให้ factory create ล้มถาวร)
 *   2. decimals ไม่ถูกตรวจ (สร้างได้ถึง 255)
 *   3. Stablecoin: renounce แล้วผู้สร้างยัง mint ได้ไม่จำกัด
 *   4. NFT: royalty แก้ทีหลังได้ 100% · จองเกิน gasLimit แล้วสร้างไม่ขึ้น · maxSupply 0 ไม่ได้แปลว่าไม่จำกัด
 *   5. เหรียญจาก factory ต้องซื้อขายผ่าน TPIX DEX ได้จริง — และ auto-burn ขายไม่ได้
 *      (เหตุผลที่หน้าแอดมินล็อก auto-burn ไว้จนกว่า router จะรองรับ fee-on-transfer)
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { deployTokenFactory } = require("./helpers/deployTokenFactory");

const E18 = 10n ** 18n;
const SUPPLY = 1_000_000n * E18;
const ZERO = ethers.ZeroAddress;

async function createdAddress(tx, factory) {
    const receipt = await tx.wait();
    const log = receipt.logs
        .map((l) => { try { return factory.interface.parseLog(l); } catch { return null; } })
        .find((l) => l && (l.name === "TokenCreated" || l.name === "NFTCreated"));
    return log.args[0];
}

describe("TPIX Token Factory — ด่านความปลอดภัย", function () {
    let owner, user, outsider;
    let creators, tokenFactory, nftFactory;

    beforeEach(async function () {
        [owner, user, outsider] = await ethers.getSigners();
        ({ creators, tokenFactory, nftFactory } = await deployTokenFactory());
    });

    // ═══════════════════════════════════════════════════════════
    describe("1. creator รับคำสั่งจาก factory ที่ผูกไว้เท่านั้น", function () {
        it("คนนอกเรียก create() ของ creator ตรง ๆ ไม่ได้", async function () {
            const salt = ethers.id("front-run");
            await expect(
                creators.ERC20V2Creator.connect(outsider).create(
                    salt, "Fake", "FAKE", 77, SUPPLY, outsider.address,
                    false, false, false, false, 0, false, 0, 0
                )
            ).to.be.revertedWithCustomError(creators.ERC20V2Creator, "NotFactory");
        });

        it("แม้แต่กระเป๋าที่ deploy creator ก็เรียก create() ตรงไม่ได้", async function () {
            await expect(
                creators.NFTCollectionCreator.connect(owner).create(
                    ethers.id("x"), "C", "C", owner.address, 10, 0, 0, 1, 1, 0, "", "", false, false, ZERO, 0
                )
            ).to.be.revertedWithCustomError(creators.NFTCollectionCreator, "NotFactory");
        });

        it("ผูก factory ได้ครั้งเดียว โดย deployer เท่านั้น และห้ามผูกกับ address(0)", async function () {
            const C = await ethers.getContractFactory("ERC20V2Creator");
            const fresh = await C.deploy();
            await expect(fresh.connect(outsider).bindFactory(outsider.address))
                .to.be.revertedWithCustomError(fresh, "NotDeployer");
            await expect(fresh.bindFactory(ZERO)).to.be.revertedWithCustomError(fresh, "ZeroFactory");
            await expect(fresh.bindFactory(tokenFactory.target))
                .to.emit(fresh, "FactoryBound").withArgs(tokenFactory.target);
            await expect(fresh.bindFactory(outsider.address))
                .to.be.revertedWithCustomError(fresh, "FactoryAlreadyBound");
            expect(await fresh.factory()).to.equal(tokenFactory.target);
        });

        it("ทุก creator ผูกกับ factory ที่ถูกตัว", async function () {
            for (const n of ["ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator",
                "GovernanceTokenCreator", "StablecoinTokenCreator"]) {
                expect(await creators[n].factory(), n).to.equal(tokenFactory.target);
            }
            expect(await creators.FactoryERC721Creator.factory()).to.equal(nftFactory.target);
            expect(await creators.NFTCollectionCreator.factory()).to.equal(nftFactory.target);
        });

        it("ลืมผูก = factory สร้างไม่ได้ (ล้มดัง ไม่ใช่สร้างเงียบ ๆ)", async function () {
            const names = ["ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator",
                "GovernanceTokenCreator", "StablecoinTokenCreator"];
            const unbound = [];
            for (const n of names) {
                const c = await (await ethers.getContractFactory(n)).deploy();
                unbound.push(c.target);
            }
            const f = await (await ethers.getContractFactory("TPIXTokenFactoryV2")).deploy(...unbound);
            await expect(f.createERC20V2("A", "A", 18, SUPPLY, user.address,
                false, false, false, false, 0, false, 0, 0)).to.be.reverted;
        });

        it("factory ยังสร้างเหรียญได้ปกติหลังผูก", async function () {
            const addr = await createdAddress(await tokenFactory.createERC20V2(
                "Ok", "OK", 18, SUPPLY, user.address, false, false, false, false, 0, false, 0, 0
            ), tokenFactory);
            const t = await ethers.getContractAt("FactoryERC20V2", addr);
            expect(await t.balanceOf(user.address)).to.equal(SUPPLY);
        });
    });

    // ═══════════════════════════════════════════════════════════
    describe("2. decimals ต้องไม่เกิน 18", function () {
        it("ERC20V2 รับ 18 แต่ปฏิเสธ 19", async function () {
            await expect(tokenFactory.createERC20V2("A", "A", 19, SUPPLY, user.address,
                false, false, false, false, 0, false, 0, 0)).to.be.revertedWith("V2: decimals > 18");
            await expect(tokenFactory.createERC20V2("A", "A", 18, SUPPLY, user.address,
                false, false, false, false, 0, false, 0, 0)).to.not.be.reverted;
        });

        it("Governance และ Stablecoin ปฏิเสธ decimals 19", async function () {
            await expect(tokenFactory.createGovernanceToken("G", "G", 19, SUPPLY, user.address,
                false, false, false, false, true, 0, 0, 400, 3)).to.be.revertedWith("GOV: decimals > 18");
            await expect(tokenFactory.createStablecoinToken("S", "S", 19, SUPPLY, user.address,
                user.address, false, false, false)).to.be.revertedWith("SC: decimals > 18");
        });
    });

    // ═══════════════════════════════════════════════════════════
    describe("3. Stablecoin — เปลี่ยนเจ้าของแล้วเจ้าของเก่า mint ไม่ได้", function () {
        async function makeStable() {
            const addr = await createdAddress(await tokenFactory.createStablecoinToken(
                "Stable", "STB", 6, 1_000n * 10n ** 6n, user.address, user.address, false, false, false
            ), tokenFactory);
            return ethers.getContractAt("StablecoinToken", addr);
        }

        it("renounce แล้วผู้สร้างหมดสิทธิ์ mint", async function () {
            const sc = await makeStable();
            expect(await sc.isMinter(user.address)).to.equal(true);
            await sc.connect(user).renounceOwnership();
            expect(await sc.isMinter(user.address)).to.equal(false);
            await expect(sc.connect(user).mint(user.address, 1, "x")).to.be.reverted;
        });

        it("transferOwnership แล้วเจ้าของเก่าหมดสิทธิ์ เจ้าของใหม่ mint ได้", async function () {
            const sc = await makeStable();
            await sc.connect(user).transferOwnership(outsider.address);
            await expect(sc.connect(user).mint(user.address, 1, "x")).to.be.reverted;
            await expect(sc.connect(outsider).mint(outsider.address, 1, "x")).to.not.be.reverted;
        });
    });

    // ═══════════════════════════════════════════════════════════
    describe("4. NFT", function () {
        async function makeCollection(reserve) {
            return nftFactory.createNFTCollection(
                "Col", "COL", user.address, 500, 0, 0, 0, 10, reserve, "ipfs://b/", "", false, true, user.address, 500
            );
        }

        it("collection จองได้ไม่เกิน 100 ใบ", async function () {
            await expect(makeCollection(101)).to.be.revertedWith("COL: reserve > 100");
            await expect(makeCollection(100)).to.not.be.reverted;
        });

        it("แก้ royalty ทีหลังเกิน 50% ไม่ได้ ทั้ง collection และ NFT เดี่ยว", async function () {
            const col = await ethers.getContractAt("NFTCollection", await createdAddress(await makeCollection(0), nftFactory));
            await expect(col.connect(user).setDefaultRoyalty(user.address, 10000)).to.be.revertedWith("COL: royalty > 50%");
            await expect(col.connect(user).setDefaultRoyalty(user.address, 5000)).to.not.be.reverted;

            const nftAddr = await createdAddress(await nftFactory.createNFT(
                "N", "N", user.address, "ipfs://1", 1, false, false, true, user.address, 500
            ), nftFactory);
            const nft = await ethers.getContractAt("FactoryERC721", nftAddr);
            await expect(nft.connect(user).setDefaultRoyalty(user.address, 10000)).to.be.revertedWith("NFT: royalty > 50%");
        });

        it("NFT เดี่ยว maxSupply 0 = ไม่จำกัด (mintable แล้ว mint เพิ่มได้)", async function () {
            const addr = await createdAddress(await nftFactory.createNFT(
                "N", "N", user.address, "ipfs://1", 0, true, false, false, ZERO, 0
            ), nftFactory);
            const nft = await ethers.getContractAt("FactoryERC721", addr);
            expect(await nft.maxSupply()).to.equal(0n);
            await nft.connect(user).mint(user.address, "ipfs://2");
            await nft.connect(user).mint(user.address, "ipfs://3");
            expect(await nft.totalMinted()).to.equal(3n);
        });

        it("NFT เดี่ยว maxSupply 1 ยังเป็นใบเดียวจริง", async function () {
            const addr = await createdAddress(await nftFactory.createNFT(
                "N", "N", user.address, "ipfs://1", 1, true, false, false, ZERO, 0
            ), nftFactory);
            const nft = await ethers.getContractAt("FactoryERC721", addr);
            await expect(nft.connect(user).mint(user.address, "ipfs://2")).to.be.revertedWith("NFT: max supply reached");
        });
    });

    // ═══════════════════════════════════════════════════════════
    describe("5. เหรียญจาก factory ซื้อขายผ่าน TPIX DEX", function () {
        let wtpix, dexFactory, router;

        beforeEach(async function () {
            wtpix = await (await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX")).deploy();
            dexFactory = await (await ethers.getContractFactory("TPIXDEXFactory")).deploy(owner.address);
            router = await (await ethers.getContractFactory("TPIXDEXRouter02")).deploy(dexFactory.target, wtpix.target);
        });

        async function makeToken(autoBurn) {
            const addr = await createdAddress(await tokenFactory.createERC20V2(
                "Child", "CHD", 18, SUPPLY, user.address,
                false, true, false, false, 0, autoBurn, autoBurn ? 100 : 0, 0
            ), tokenFactory);
            const token = await ethers.getContractAt("FactoryERC20V2", addr);
            // เจ้าของเหรียญเปิดพูล token/TPIX
            await token.connect(user).approve(router.target, SUPPLY);
            const deadline = (await ethers.provider.getBlock("latest")).timestamp + 600;
            await router.connect(user).addLiquidityETH(
                token.target, 100_000n * E18, 0, 0, user.address, deadline, { value: 1_000n * E18 }
            );
            return { token, deadline };
        }

        it("standard (ไม่มี owner power) — ซื้อแล้วขายคืนได้", async function () {
            const { token, deadline } = await makeToken(false);
            await router.connect(outsider).swapExactETHForTokens(
                0, [wtpix.target, token.target], outsider.address, deadline, { value: 10n * E18 }
            );
            const bought = await token.balanceOf(outsider.address);
            expect(bought).to.be.gt(0n);

            await token.connect(outsider).approve(router.target, bought);
            await expect(router.connect(outsider).swapExactTokensForETH(
                bought, 0, [token.target, wtpix.target], outsider.address, deadline
            )).to.not.be.reverted;
            expect(await token.balanceOf(outsider.address)).to.equal(0n);
        });

        it("auto-burn — ซื้อได้แต่ขายคืนไม่ได้ (เหตุผลที่ต้องล็อกตัวเลือกนี้)", async function () {
            const { token, deadline } = await makeToken(true);
            await router.connect(outsider).swapExactETHForTokens(
                0, [wtpix.target, token.target], outsider.address, deadline, { value: 10n * E18 }
            );
            const bought = await token.balanceOf(outsider.address);
            expect(bought).to.be.gt(0n);

            await token.connect(outsider).approve(router.target, bought);
            await expect(router.connect(outsider).swapExactTokensForETH(
                bought, 0, [token.target, wtpix.target], outsider.address, deadline
            )).to.be.revertedWith("TPIX: K");
        });
    });
});
