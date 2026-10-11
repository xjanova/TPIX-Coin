/**
 * Deploy ชุด Token Factory ครบทั้งสาย เหมือน scripts/deploy-token-factory.js
 * (creator ทั้ง 7 → factory ทั้ง 2 → ผูก creator กับ factory ของมัน)
 *
 * creator รับคำสั่งจาก factory ที่ผูกไว้เท่านั้น (CreatorAccess) — ถ้าลืมผูก ทุก create*() จะ revert
 * เทสต์ทุกไฟล์จึงต้อง deploy ผ่านตัวช่วยนี้ ไม่ deploy creator เองทีละตัว
 */
const { ethers } = require("hardhat");

const ERC20_CREATORS = [
    "ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator",
    "GovernanceTokenCreator", "StablecoinTokenCreator",
];
const NFT_CREATORS = ["FactoryERC721Creator", "NFTCollectionCreator"];

async function deployTokenFactory() {
    const creators = {};
    for (const name of [...ERC20_CREATORS, ...NFT_CREATORS]) {
        const C = await ethers.getContractFactory(name);
        const c = await C.deploy();
        await c.waitForDeployment();
        creators[name] = c;
    }

    const TF = await ethers.getContractFactory("TPIXTokenFactoryV2");
    const tokenFactory = await TF.deploy(...ERC20_CREATORS.map((n) => creators[n].target));
    await tokenFactory.waitForDeployment();

    const NF = await ethers.getContractFactory("TPIXNFTFactory");
    const nftFactory = await NF.deploy(...NFT_CREATORS.map((n) => creators[n].target));
    await nftFactory.waitForDeployment();

    for (const n of ERC20_CREATORS) await (await creators[n].bindFactory(tokenFactory.target)).wait();
    for (const n of NFT_CREATORS) await (await creators[n].bindFactory(nftFactory.target)).wait();

    return { creators, tokenFactory, nftFactory };
}

module.exports = { deployTokenFactory, ERC20_CREATORS, NFT_CREATORS };
