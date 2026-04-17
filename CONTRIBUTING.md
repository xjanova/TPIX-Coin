# Contributing to TPIX Chain

Thanks for your interest in contributing! TPIX Chain is open infrastructure for the ASEAN digital economy, and we welcome contributions from developers, researchers, auditors, and the community.

## Ways to Contribute

| Type | Where | Notes |
|------|-------|-------|
| **Bug reports** (non-security) | [GitHub Issues](https://github.com/xjanova/TPIX-Coin/issues) | Use the bug template |
| **Security reports** | security@tpix.online | See [SECURITY.md](SECURITY.md) — **never** a public issue |
| **Feature requests** | [GitHub Discussions](https://github.com/xjanova/TPIX-Coin/discussions) | Propose first, code after |
| **Code contributions** | Pull Requests | See workflow below |
| **Documentation** | Pull Requests to `docs/` | README and WHITEPAPER welcome |
| **Translations** | Pull Requests | Thai, English, Vietnamese, Bahasa, Khmer |
| **Validator nodes** | [masternode/guide](https://tpix.online/masternode/guide) | 10M TPIX + KYC required |

## Development Workflow

### 1. Setup

```bash
git clone https://github.com/xjanova/TPIX-Coin.git
cd TPIX-Coin

# Contracts
cd contracts && npm install

# Wallet (Flutter)
cd ../wallet && flutter pub get

# Masternode UI (Electron)
cd ../masternode-ui && npm install
```

### 2. Branch Naming

- `feat/<short-description>` — new feature
- `fix/<short-description>` — bug fix
- `docs/<short-description>` — documentation only
- `chore/<short-description>` — tooling, deps, CI
- `refactor/<short-description>` — non-functional code change

### 3. Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

- **Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `build`, `ci`
- **Scope:** `wallet`, `masternode-ui`, `contracts`, `dex`, `bridge`, `identity`, `explorer`, `docs`
- **Subject:** imperative, no period, ≤ 72 chars

Example: `feat(contracts): add bulk-mint function to NFTCollection`

### 4. Pull Request Checklist

- [ ] Code compiles / builds without warnings
- [ ] Tests added/updated for new behavior
- [ ] Documentation updated (README, comments, whitepaper if relevant)
- [ ] Commit messages follow Conventional Commits
- [ ] Scenario-based review performed (see below)
- [ ] No merge conflicts with `main`

### 5. Scenario-Based Review (Required)

Every code change must be mentally traced through real-world scenarios **before** requesting review. See [docs/CODE_REVIEW.md](docs/CODE_REVIEW.md) — minimum coverage:

- First-time user / empty state
- Happy path
- User error / invalid input
- Network failure / timeout
- Rapid taps / double-submit
- Concurrent state change

For security-critical code (contracts, auth, wallet): additionally trace through:

- Input injection
- Reentrancy / race conditions
- Privilege escalation
- Signature replay

## Smart Contract Contributions

### Style

- Solidity 0.8.20 or 0.8.24 (match existing pragma in each folder)
- OpenZeppelin 5.x imports only — no legacy 4.x
- NatSpec comments on all external/public functions
- Explicit visibility on every function
- `immutable` for constructor-set values when possible
- `unchecked` blocks only with a justifying comment

### Testing

```bash
cd contracts
npm test                # hardhat test
npm run coverage        # solidity-coverage (>= 80% required for new code)
npm run gas             # gas usage report
```

### Security Checks

Before submitting:

```bash
npm run slither         # static analysis (install slither first)
npm run mythril         # symbolic execution (optional, slow)
```

Address every high/medium finding or justify in PR description.

## Frontend (Wallet / Masternode UI / DEX)

- Follow the existing UI patterns (glass-morphism dark theme)
- Thai + English bilingual strings in the same commit
- Test on both platforms (Android + iOS for wallet; Windows for UI)
- No `console.log` statements in production code paths
- Respect `CLAUDE.md` scenario checklist per repo

## Documentation

- Markdown linted with Prettier (`npx prettier --write docs/*.md`)
- Links must resolve (no broken links)
- Screenshots go in `docs/images/` as optimized WebP/PNG
- Match the voice/tone of existing docs

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE) — the same license as the project.

## Code of Conduct

- Be respectful, inclusive, and constructive
- No harassment, personal attacks, or discriminatory language
- Focus on technical merit, not personal opinions about contributors
- Follow the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/)

Violations may result in removal from the project. Report incidents to conduct@tpix.online.

## Questions?

- **Technical:** GitHub Discussions
- **Community:** [Telegram](https://t.me/tpixchain) *(coming soon)*
- **Business / Partnership:** contact@tpix.online

Thank you for contributing! 🙏
