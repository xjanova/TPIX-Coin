const { expect } = require("chai");
const { ethers, artifacts } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * Pre-deployment audit tests for TPIXBridgeMinter (adversarial).
 *
 * Complements TPIXBridgeMinter.test.js with:
 *   - EVM compatibility guard: polygon-edge 0.9 (london) has no PUSH0/MCOPY/TSTORE/TLOAD/BLOBHASH/BLOBBASEFEE
 *   - fuzzing of maxPerTx / dailyCap across UTC day boundaries against a reference model
 *   - depositId replay in every state the minter can be in (new day, unpause, rotated relayer, raised caps,
 *     a second minter on the same token)
 *   - the pause/unpause permission matrix for every role
 *   - compromised-relayer and compromised-owner worst cases, so the residual risk is written down as code
 */
describe("TPIXBridgeMinter — audit", function () {
    const DAY = 86400;
    const U = (n) => ethers.parseUnits(String(n), 6);
    const MAX_PER_TX = U(1000);
    const DAILY_CAP = U(5000);

    let idCounter = 0n;
    const freshId = () => ethers.keccak256(ethers.toBeHex(++idCounter + 0xa0d17n, 32));
    const depositId = (chainId, txHash, logIndex) => ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "bytes32", "uint256"], [chainId, txHash, logIndex]),
    );

    /** deterministic xorshift32 so a failing seed can be replayed */
    function prng(seed) {
        let s = seed >>> 0 || 1;
        return () => {
            s ^= s << 13; s >>>= 0;
            s ^= s >>> 17;
            s ^= s << 5; s >>>= 0;
            return s / 0x100000000;
        };
    }

    async function deployFixture() {
        const [owner, relayer, relayer2, guardian, alice, bob, attacker, stranger] = await ethers.getSigners();
        const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        const minter = await (await ethers.getContractFactory("TPIXBridgeMinter"))
            .deploy(await usdt.getAddress(), MAX_PER_TX, DAILY_CAP);
        await usdt.setBridge(await minter.getAddress(), true);
        await minter.setRelayer(relayer.address, true);
        await minter.setGuardian(guardian.address, true);
        return { usdt, minter, owner, relayer, relayer2, guardian, alice, bob, attacker, stranger };
    }

    /** jump to `secondsIntoDay` of the next UTC day so tests never straddle midnight by accident */
    async function goToNextDay(secondsIntoDay = 60) {
        const now = await time.latest();
        const target = (Math.floor(now / DAY) + 1) * DAY + secondsIntoDay;
        await time.setNextBlockTimestamp(target);
        await ethers.provider.send("evm_mine", []);
        return target;
    }

    /**
     * try a mint mined at an exact timestamp; returns true on success, false on revert.
     * A fixed gasLimit skips estimateGas, so the tx is always mined in a block with timestamp `ts`
     * (a revert is then decided by the real block, not by a pending-block estimate).
     */
    async function mintAt(minter, signer, ts, to, amount, id) {
        await time.setNextBlockTimestamp(ts);
        try {
            const tx = await minter.connect(signer).mint(to, amount, id, { gasLimit: 300_000 });
            const receipt = await tx.wait();
            return receipt.status === 1;
        } catch (e) {
            if (!/revert|CALL_EXCEPTION/i.test(String(e.message || e.code))) throw e;
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    describe("EVM compatibility (polygon-edge 0.9 = london)", function () {
        // opcodes introduced after london — any of them in reachable code = "opcode not found" on TPIX Chain
        const FORBIDDEN = { 0x5f: "PUSH0", 0x5e: "MCOPY", 0x5c: "TLOAD", 0x5d: "TSTORE", 0x49: "BLOBHASH", 0x4a: "BLOBBASEFEE" };

        /** drop the CBOR metadata trailer (its length is the last 2 bytes) — it is data, not code */
        function stripMetadata(hex) {
            const bytes = ethers.getBytes(hex);
            const len = (bytes[bytes.length - 2] << 8) | bytes[bytes.length - 1];
            return bytes.slice(0, bytes.length - 2 - len);
        }

        /** linear sweep that skips PUSH immediates */
        function scan(bytes) {
            const found = [];
            for (let i = 0; i < bytes.length; i++) {
                const op = bytes[i];
                if (FORBIDDEN[op]) found.push(`${FORBIDDEN[op]}@${i}`);
                if (op >= 0x60 && op <= 0x7f) i += op - 0x5f;
            }
            return found;
        }

        it("runtime code and initcode contain no post-london opcode", async function () {
            const art = await artifacts.readArtifact("TPIXBridgeMinter");
            const runtime = stripMetadata(art.deployedBytecode);
            expect(scan(runtime), "runtime").to.deep.equal([]);

            // initcode = constructor code + embedded runtime (+ metadata). Sweep the constructor part only:
            // it ends where the runtime copy starts.
            const init = ethers.getBytes(art.bytecode);
            const runtimeFull = ethers.getBytes(art.deployedBytecode);
            const runtimeStart = Buffer.from(init).indexOf(Buffer.from(runtimeFull));
            expect(runtimeStart, "runtime embedded in initcode").to.be.greaterThan(0);
            expect(scan(init.slice(0, runtimeStart)), "constructor").to.deep.equal([]);
        });

        it("initcode is far below the rpc1 nginx body limit and runtime below EIP-170", async function () {
            const art = await artifacts.readArtifact("TPIXBridgeMinter");
            const initBytes = (art.bytecode.length - 2) / 2 + 3 * 32; // + abi-encoded constructor args
            const runtimeBytes = (art.deployedBytecode.length - 2) / 2;
            // a signed raw tx is hex in JSON: ~2 chars per byte + envelope — 15.9 KB initcode ≈ 32 KB body
            expect(initBytes).to.be.lessThan(15_900);
            expect(runtimeBytes).to.be.lessThan(24_576);
        });

        it("was compiled for london with the optimizer (hardhat.config pin)", async function () {
            const fqn = "src/bridge/TPIXBridgeMinter.sol:TPIXBridgeMinter";
            const info = await artifacts.getBuildInfo(fqn);
            expect(info.solcVersion).to.equal("0.8.24");
            expect(info.input.settings.evmVersion).to.equal("london");
            expect(info.input.settings.optimizer.enabled).to.equal(true);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    describe("caps across UTC day boundaries", function () {
        it("a mint at 23:59:59 and one at 00:00:00 land in different days", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            const start = await goToNextDay(DAY - 120);
            const day = Math.floor(start / DAY);
            const lastSecond = (day + 1) * DAY - 1;

            for (let i = 0; i < 5; i++) {
                expect(await mintAt(minter, relayer, lastSecond - 10 + i, alice.address, MAX_PER_TX, freshId())).to.equal(true);
            }
            expect(await minter.mintedPerDay(day)).to.equal(DAILY_CAP);
            expect(await mintAt(minter, relayer, lastSecond, alice.address, 1n, freshId())).to.equal(false);

            // exactly midnight belongs to the new day
            expect(await mintAt(minter, relayer, (day + 1) * DAY, alice.address, MAX_PER_TX, freshId())).to.equal(true);
            expect(await minter.mintedPerDay(day + 1)).to.equal(MAX_PER_TX);
            expect(await minter.mintedPerDay(day)).to.equal(DAILY_CAP);
        });

        it("many tiny mints cannot bypass the daily cap (maxPerTx splitting)", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            await goToNextDay(60);
            await minter.setMaxPerTx(U(1));
            await minter.setDailyCap(U(25));
            for (let i = 0; i < 25; i++) {
                await minter.connect(relayer).mint(alice.address, U(1), freshId());
            }
            await expect(minter.connect(relayer).mint(alice.address, 1n, freshId()))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap").withArgs(1n, 0n);
        });

        it("two relayers share one daily cap", async function () {
            const { minter, relayer, relayer2, alice } = await loadFixture(deployFixture);
            await minter.setRelayer(relayer2.address, true);
            await goToNextDay(60);
            for (let i = 0; i < 3; i++) await minter.connect(relayer).mint(alice.address, MAX_PER_TX, freshId());
            for (let i = 0; i < 2; i++) await minter.connect(relayer2).mint(alice.address, MAX_PER_TX, freshId());
            await expect(minter.connect(relayer2).mint(alice.address, 1n, freshId()))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap");
            await expect(minter.connect(relayer).mint(alice.address, 1n, freshId()))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap");
        });

        for (const seed of [0x1234, 0xbeef, 0xc0ffee, 0x7a1d, 0x4289]) {
            it(`fuzz vs reference model (seed 0x${seed.toString(16)})`, async function () {
                const { usdt, minter, owner, relayer, guardian, alice } = await loadFixture(deployFixture);
                const rnd = prng(seed);
                const pick = (n) => Math.floor(rnd() * n);

                let maxPerTx = MAX_PER_TX;
                let dailyCap = DAILY_CAP;
                let maxCapEver = DAILY_CAP;
                let paused = false;
                const used = new Map();
                const usedIds = [];
                const mints = []; // [timestamp, amount] of every accepted mint
                let total = 0n;
                let capRejections = 0;

                // start a few minutes before a midnight so the run crosses several boundaries
                let ts = await goToNextDay(DAY - 300);

                for (let step = 0; step < 220; step++) {
                    // time: mostly seconds, sometimes jump to just before / exactly at / after midnight, or days
                    const r = rnd();
                    if (r < 0.55) ts += 1 + pick(90);
                    else if (r < 0.70) ts = (Math.floor(ts / DAY) + 1) * DAY - 1 - pick(3); // 23:59:5x
                    else if (r < 0.80) ts = (Math.floor(ts / DAY) + 1) * DAY;              // 00:00:00
                    else if (r < 0.93) ts += 600 + pick(4 * 3600);
                    else ts += DAY * (1 + pick(3));
                    const latest = await time.latest();
                    if (ts <= latest) ts = latest + 1;

                    const action = rnd();
                    if (action < 0.05) {
                        // owner retunes caps (keeps maxPerTx <= dailyCap, otherwise expect a revert)
                        const newCap = U(1 + pick(8000));
                        await time.setNextBlockTimestamp(ts);
                        if (newCap >= maxPerTx) {
                            await minter.connect(owner).setDailyCap(newCap);
                            dailyCap = newCap;
                            if (newCap > maxCapEver) maxCapEver = newCap;
                        } else {
                            await expect(minter.connect(owner).setDailyCap(newCap)).to.be.revertedWithCustomError(minter, "InvalidCaps");
                        }
                        continue;
                    }
                    if (action < 0.08) {
                        const newMax = U(1 + pick(1500));
                        await time.setNextBlockTimestamp(ts);
                        if (newMax <= dailyCap) {
                            await minter.connect(owner).setMaxPerTx(newMax);
                            maxPerTx = newMax;
                        } else {
                            await expect(minter.connect(owner).setMaxPerTx(newMax)).to.be.revertedWithCustomError(minter, "InvalidCaps");
                        }
                        continue;
                    }
                    if (action < 0.11) {
                        await time.setNextBlockTimestamp(ts);
                        if (paused) await minter.connect(owner).unpause();
                        else await minter.connect(guardian).pause();
                        paused = !paused;
                        continue;
                    }

                    // a mint — sometimes a replayed id, sometimes oversized, sometimes zero
                    const replay = usedIds.length > 0 && rnd() < 0.1;
                    const id = replay ? usedIds[pick(usedIds.length)] : freshId();
                    const roll = rnd();
                    const amount = roll < 0.03 ? 0n
                        : roll < 0.12 ? maxPerTx + BigInt(1 + pick(1000))
                        : roll < 0.45 ? maxPerTx
                        : BigInt(1 + pick(Number(maxPerTx)));

                    const day = Math.floor(ts / DAY);
                    const dayUsed = used.get(day) || 0n;
                    const expectOk = !paused && !replay && amount > 0n && amount <= maxPerTx && dayUsed + amount <= dailyCap;

                    const ok = await mintAt(minter, relayer, ts, alice.address, amount, id);
                    expect(ok, `step ${step} day ${day} used ${dayUsed} amt ${amount} cap ${dailyCap} max ${maxPerTx} paused ${paused} replay ${replay}`)
                        .to.equal(expectOk);

                    if (!ok && !paused && !replay && amount > 0n && amount <= maxPerTx) capRejections++;
                    if (ok) {
                        used.set(day, dayUsed + amount);
                        usedIds.push(id);
                        mints.push([ts, amount]);
                        total += amount;
                    }
                    expect(await minter.mintedPerDay(day)).to.equal(used.get(day) || 0n);
                }

                // the run must actually have exercised the interesting paths
                expect(mints.length, "accepted mints").to.be.greaterThan(20);
                expect(capRejections, "daily-cap rejections").to.be.greaterThan(3);
                expect(used.size, "distinct UTC days with mints").to.be.greaterThan(3);

                // global invariants
                expect(await minter.totalMinted()).to.equal(total);
                expect(await usdt.totalSupply()).to.equal(total);
                expect(await usdt.totalEverMinted()).to.equal(total);
                for (const [day, amount] of used) {
                    expect(await minter.mintedPerDay(day)).to.equal(amount);
                }

                // no rolling 24h window ever exceeds 2 × the largest cap that was in force (documented edge)
                const ceiling = 2n * maxCapEver;
                for (let i = 0; i < mints.length; i++) {
                    let sum = 0n;
                    for (let j = i; j < mints.length && mints[j][0] < mints[i][0] + DAY; j++) sum += mints[j][1];
                    expect(sum <= ceiling).to.equal(true);
                }
            });
        }

        it("burst fuzz with fixed caps: any rolling 24h window ≤ 2 × dailyCap, any UTC day ≤ dailyCap", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            const rnd = prng(0xfeed);
            let ts = await goToNextDay(DAY - 900);
            const mints = [];

            for (let step = 0; step < 160; step++) {
                ts += 1 + Math.floor(rnd() * (rnd() < 0.2 ? 20000 : 60));
                const latest = await time.latest();
                if (ts <= latest) ts = latest + 1;
                if (await mintAt(minter, relayer, ts, alice.address, MAX_PER_TX, freshId())) mints.push(ts);
            }

            const perDay = new Map();
            for (const t of mints) perDay.set(Math.floor(t / DAY), (perDay.get(Math.floor(t / DAY)) || 0n) + MAX_PER_TX);
            for (const v of perDay.values()) expect(v <= DAILY_CAP).to.equal(true);

            let worst = 0n;
            for (let i = 0; i < mints.length; i++) {
                let sum = 0n;
                for (let j = i; j < mints.length && mints[j] < mints[i] + DAY; j++) sum += MAX_PER_TX;
                if (sum > worst) worst = sum;
            }
            expect(worst <= 2n * DAILY_CAP).to.equal(true);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    describe("depositId replay protection", function () {
        it("a deposit id stays spent forever: next day, after pause/unpause, rotated relayer, raised caps", async function () {
            const { usdt, minter, owner, relayer, relayer2, guardian, alice, bob } = await loadFixture(deployFixture);
            const id = depositId(56, ethers.keccak256("0x01"), 3);
            await minter.connect(relayer).mint(alice.address, U(10), id);

            const replay = (signer, to = bob.address, amount = U(10)) =>
                expect(minter.connect(signer).mint(to, amount, id)).to.be.revertedWith("USDT_TPIX: txhash replayed");

            await replay(relayer);
            await replay(relayer, alice.address, U(1)); // different recipient / amount does not help

            await time.increase(DAY * 3);
            await replay(relayer);

            await minter.connect(guardian).pause();
            await minter.connect(owner).unpause();
            await replay(relayer);

            await minter.setRelayer(relayer.address, false);
            await minter.setRelayer(relayer2.address, true);
            await replay(relayer2);

            await minter.setDailyCap(U(1_000_000));
            await minter.setMaxPerTx(U(1_000_000));
            await replay(relayer2);

            expect(await minter.isProcessed(id)).to.equal(true);
            expect(await usdt.balanceOf(bob.address)).to.equal(0n);
        });

        it("a second minter on the same token cannot replay ids spent through the first (state lives in USDT_TPIX)", async function () {
            const { usdt, minter, relayer, alice } = await loadFixture(deployFixture);
            const id = freshId();
            await minter.connect(relayer).mint(alice.address, U(5), id);

            const minter2 = await (await ethers.getContractFactory("TPIXBridgeMinter"))
                .deploy(await usdt.getAddress(), MAX_PER_TX, DAILY_CAP);
            await usdt.setBridge(await minter2.getAddress(), true);
            await minter2.setRelayer(relayer.address, true);

            await expect(minter2.connect(relayer).mint(alice.address, U(5), id)).to.be.revertedWith("USDT_TPIX: txhash replayed");
            expect(await minter2.isProcessed(id)).to.equal(true);
        });

        it("the same source tx with two Transfer logs yields two distinct ids (log index is part of the id)", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            const tx = ethers.keccak256("0xabcd");
            await minter.connect(relayer).mint(alice.address, U(1), depositId(1, tx, 7));
            await minter.connect(relayer).mint(alice.address, U(1), depositId(1, tx, 8));
            // same tx hash on another chain is another deposit
            await minter.connect(relayer).mint(alice.address, U(1), depositId(56, tx, 7));
            await expect(minter.connect(relayer).mint(alice.address, U(1), depositId(1, tx, 7)))
                .to.be.revertedWith("USDT_TPIX: txhash replayed");
        });

        it("a reverted replay consumes neither quota nor totals (whole tx rolls back)", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            await goToNextDay(60);
            const id = freshId();
            await minter.connect(relayer).mint(alice.address, MAX_PER_TX, id);
            for (let i = 0; i < 10; i++) {
                await expect(minter.connect(relayer).mint(alice.address, MAX_PER_TX, id)).to.be.reverted;
            }
            expect(await minter.remainingToday()).to.equal(DAILY_CAP - MAX_PER_TX);
            expect(await minter.totalMinted()).to.equal(MAX_PER_TX);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    describe("pause / unpause permission matrix", function () {
        it("who can pause and unpause", async function () {
            const f = await loadFixture(deployFixture);
            const { minter, owner, guardian, relayer, stranger, attacker } = f;
            await minter.transferOwnership(attacker.address); // attacker = pendingOwner, not owner yet

            for (const s of [relayer, stranger, attacker]) {
                await expect(minter.connect(s).pause()).to.be.revertedWithCustomError(minter, "NotGuardian");
            }
            await minter.connect(guardian).pause();
            for (const s of [guardian, relayer, stranger, attacker]) {
                await expect(minter.connect(s).unpause()).to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
            }
            await minter.connect(owner).unpause();
            await minter.connect(owner).pause();
            await expect(minter.connect(owner).pause()).to.be.revertedWithCustomError(minter, "EnforcedPause");
            await minter.connect(owner).unpause();
            await expect(minter.connect(owner).unpause()).to.be.revertedWithCustomError(minter, "ExpectedPause");
        });

        it("while paused the owner can still rotate keys, change caps and move ownership", async function () {
            const { minter, owner, guardian, relayer, relayer2, alice, bob } = await loadFixture(deployFixture);
            await minter.connect(guardian).pause();

            await minter.setRelayer(relayer.address, false);
            await minter.setRelayer(relayer2.address, true);
            await minter.setGuardian(guardian.address, false);
            await minter.setMaxPerTx(U(10));
            await minter.setDailyCap(U(100));
            await minter.transferOwnership(bob.address);
            await minter.connect(bob).acceptOwnership();

            await expect(minter.connect(relayer2).mint(alice.address, U(1), freshId()))
                .to.be.revertedWithCustomError(minter, "EnforcedPause");
            await expect(minter.connect(owner).unpause()).to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
            await minter.connect(bob).unpause();
            await minter.connect(relayer2).mint(alice.address, U(1), freshId());
            await expect(minter.connect(relayer).mint(alice.address, U(1), freshId()))
                .to.be.revertedWithCustomError(minter, "NotRelayer");
        });

        it("pausing the minter does not freeze withdrawals: holders can still bridgeBurn on USDT_TPIX", async function () {
            const { usdt, minter, guardian, relayer, alice } = await loadFixture(deployFixture);
            await minter.connect(relayer).mint(alice.address, U(50), freshId());
            await minter.connect(guardian).pause();
            await expect(usdt.connect(alice).bridgeBurn(U(20), 56, alice.address))
                .to.emit(usdt, "Burned").withArgs(alice.address, U(20), 56, alice.address);
            expect(await usdt.totalSupply()).to.equal(U(30));
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    describe("compromised relayer key (worst case)", function () {
        /** attacker mints maxPerTx with fresh ids until the minter refuses; returns what got through */
        async function drain(minter, attackerRelayer, to, fromTs) {
            let ts = fromTs;
            let got = 0n;
            for (let i = 0; i < 20; i++) {
                const latest = await time.latest();
                if (ts <= latest) ts = latest + 1;
                if (await mintAt(minter, attackerRelayer, ts, to, MAX_PER_TX, freshId())) got += MAX_PER_TX;
                ts += 1;
            }
            return got;
        }

        it("loss inside one UTC day is bounded by dailyCap; around midnight by 2 × dailyCap", async function () {
            const { usdt, minter, relayer, attacker } = await loadFixture(deployFixture);
            const start = await goToNextDay(DAY - 40);

            const before = await drain(minter, relayer, attacker.address, start + 1);
            expect(before).to.equal(DAILY_CAP);

            const midnight = (Math.floor(start / DAY) + 1) * DAY;
            const after = await drain(minter, relayer, attacker.address, midnight);
            expect(after).to.equal(DAILY_CAP);

            const elapsed = (await time.latest()) - (start + 1);
            expect(elapsed).to.be.lessThan(120); // 10,000 USDT in under two minutes
            expect(await usdt.balanceOf(attacker.address)).to.equal(2n * DAILY_CAP);
        });

        it("undetected for N days = N × dailyCap; after the guardian pauses = zero", async function () {
            const { usdt, minter, guardian, relayer, attacker } = await loadFixture(deployFixture);
            let ts = await goToNextDay(60);
            for (let d = 0; d < 4; d++) {
                await drain(minter, relayer, attacker.address, ts);
                ts += DAY;
            }
            expect(await usdt.balanceOf(attacker.address)).to.equal(4n * DAILY_CAP);

            await minter.connect(guardian).pause();
            for (let d = 0; d < 2; d++) {
                ts += DAY;
                expect(await drain(minter, relayer, attacker.address, ts)).to.equal(0n);
            }
            expect(await usdt.balanceOf(attacker.address)).to.equal(4n * DAILY_CAP);
        });

        it("the relayer key cannot widen its own limits or reach the token directly", async function () {
            const { usdt, minter, relayer, attacker } = await loadFixture(deployFixture);
            const m = minter.connect(relayer);
            const unauth = "OwnableUnauthorizedAccount";
            await expect(m.setDailyCap(U(10_000_000))).to.be.revertedWithCustomError(minter, unauth);
            await expect(m.setMaxPerTx(U(5000))).to.be.revertedWithCustomError(minter, unauth);
            await expect(m.setRelayer(attacker.address, true)).to.be.revertedWithCustomError(minter, unauth);
            await expect(m.setGuardian(attacker.address, true)).to.be.revertedWithCustomError(minter, unauth);
            await expect(m.unpause()).to.be.revertedWithCustomError(minter, unauth);
            await expect(m.transferOwnership(attacker.address)).to.be.revertedWithCustomError(minter, unauth);
            await expect(m.renounceOwnership()).to.be.revertedWithCustomError(minter, unauth);
            await expect(m.pause()).to.be.revertedWithCustomError(minter, "NotGuardian");

            const t = usdt.connect(relayer);
            await expect(t.bridgeMint(attacker.address, 1n, freshId())).to.be.revertedWith("USDT_TPIX: not a bridge");
            await expect(t.setBridge(relayer.address, true)).to.be.revertedWithCustomError(usdt, unauth);
            await expect(t.pause()).to.be.revertedWithCustomError(usdt, unauth);
        });

        it("RESIDUAL (off-chain detection gap): the key can front-run a real deposit id to its own address", async function () {
            // depositId = keccak(chainId, txHash, logIndex) is computable by anyone from the public source-chain log.
            // The contract cannot know the real recipient, so the stolen mint looks exactly like a normal one:
            // minter.totalMinted and USDT_TPIX.totalSupply match the vault, and the honest relayer's mint
            // reverts "txhash replayed". ThaiXTrade must compare the Minted(to, amount) log with its own record
            // whenever it finds an id already processed that it did not mint itself.
            const { usdt, minter, relayer, attacker, alice } = await loadFixture(deployFixture);
            const realDeposit = depositId(1, ethers.keccak256("0x5eed"), 42); // alice deposited 700 USDT on Ethereum

            await expect(minter.connect(relayer).mint(attacker.address, U(700), realDeposit))
                .to.emit(usdt, "Minted").withArgs(attacker.address, U(700), realDeposit);

            await expect(minter.connect(relayer).mint(alice.address, U(700), realDeposit))
                .to.be.revertedWith("USDT_TPIX: txhash replayed");
            expect(await minter.isProcessed(realDeposit)).to.equal(true);
            expect(await minter.totalMinted()).to.equal(U(700)); // == what the relayer DB believes was minted
            expect(await usdt.balanceOf(alice.address)).to.equal(0n);
        });
    });

    // ─────────────────────────────────────────────────────────────────────────
    describe("compromised owner keys (residual risk, not bounded by the minter)", function () {
        it("the USDT_TPIX owner can bypass the minter entirely: setBridge(self) + unlimited bridgeMint", async function () {
            const { usdt, owner } = await loadFixture(deployFixture);
            await usdt.connect(owner).setBridge(owner.address, true);
            const huge = U(1_000_000_000);
            await usdt.connect(owner).bridgeMint(owner.address, huge, freshId());
            expect(await usdt.balanceOf(owner.address)).to.equal(huge);
        });

        it("the USDT_TPIX owner can freeze every transfer (DEX pools included) with pause()", async function () {
            const { usdt, minter, owner, relayer, alice, bob } = await loadFixture(deployFixture);
            await minter.connect(relayer).mint(alice.address, U(10), freshId());
            await usdt.connect(owner).pause();
            await expect(usdt.connect(alice).transfer(bob.address, 1n)).to.be.revertedWithCustomError(usdt, "EnforcedPause");
            await expect(usdt.connect(alice).bridgeBurn(1n, 56, alice.address)).to.be.revertedWithCustomError(usdt, "EnforcedPause");
        });

        it("the minter owner can lift the caps and add itself as relayer", async function () {
            const { usdt, minter, owner } = await loadFixture(deployFixture);
            await minter.setDailyCap(ethers.MaxUint256 / 2n);
            await minter.setMaxPerTx(ethers.MaxUint256 / 2n);
            await minter.setRelayer(owner.address, true);
            await minter.mint(owner.address, U(1_000_000_000), freshId());
            expect(await usdt.balanceOf(owner.address)).to.equal(U(1_000_000_000));
        });
    });
});
