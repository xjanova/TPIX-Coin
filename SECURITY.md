# Security Policy

## Supported Components

| Component | Branch | Security Updates |
|-----------|--------|------------------|
| TPIX Chain (Polygon Edge nodes) | `main` | Yes |
| Smart contracts (deployed) | `main` | Yes — coordinated disclosure |
| TPIX Wallet (mobile) | latest release | Yes |
| Masternode UI (Electron) | latest release | Yes |
| DEX frontend ([tpix.online](https://tpix.online)) | prod | Yes |
| Block Explorer ([explorer.tpix.online](https://explorer.tpix.online)) | prod | Yes |

## Reporting a Vulnerability

**Please do NOT open public GitHub issues for security vulnerabilities.**

### Contact

- **Primary:** security@tpix.online
- **PGP:** *(published upon request — email us first)*
- **Anonymous:** via [Immunefi](https://immunefi.com) *(bug bounty program — planned)*

### What to Include

- Clear description of the vulnerability
- Steps to reproduce (proof of concept)
- Affected component / contract address / chain / version
- Impact assessment (funds at risk, data exposure, availability)
- Proposed remediation (optional)

### Response Timeline

| Severity | Initial Response | Patch Target |
|----------|------------------|--------------|
| Critical (funds at risk, chain halt) | < 12 hours | < 48 hours |
| High (privilege escalation, data leak) | < 24 hours | < 7 days |
| Medium (DoS, information disclosure) | < 72 hours | < 30 days |
| Low (minor UX, non-security bugs) | < 1 week | next release |

### Disclosure Policy

We follow **coordinated disclosure**:

1. You report privately to security@tpix.online.
2. We acknowledge within the response window above.
3. We investigate, develop, and test a fix.
4. We coordinate a disclosure date with you (typically 30-90 days).
5. We deploy the fix; you may publish a writeup after deployment.
6. We credit you in the changelog (unless you prefer anonymity).

### Out of Scope

- Vulnerabilities in third-party services (Blockscout upstream, Polygon Edge upstream — please report to those projects directly)
- Denial of service via resource exhaustion on public RPC (we rate-limit; a flood attack is expected to degrade service)
- Social engineering of the team
- Physical attacks or theft of team devices
- Spam or phishing campaigns targeting users
- Issues in dependencies already disclosed upstream (please link to the upstream CVE)

### Rewards

A formal bug bounty program on **Immunefi** is planned. Until then, we reward high-impact reports with:

- Credit in the changelog and hall of fame
- TPIX rewards at the team's discretion
- Swag and exchange listings announcements

Severity scoring follows [Immunefi Vulnerability Severity Classification System v2.3](https://immunefi.com/immunefi-vulnerability-severity-classification-system-v2-3/).

## Smart Contract Security

- **Deployed contracts:** verify source on [explorer.tpix.online](https://explorer.tpix.online) before interacting
- **OpenZeppelin 5.x** used for all standard primitives (ERC-20, ERC-721, AccessControl, Ownable)
- **External audits:** *planned — see [Roadmap](README.md#roadmap)*
- **Reentrancy:** all state-changing external calls use checks-effects-interactions or `ReentrancyGuard`
- **Upgradeability:** identity + token factory contracts are non-upgradeable by design (immutable once deployed)

## Key Contact Addresses

Treasury and allocation pool addresses are documented in [docs/WHITEPAPER.md](docs/WHITEPAPER.md#tokenomics). Anyone can independently verify balances via:

```bash
curl -X POST https://rpc.tpix.online \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0x<address>","latest"],"id":1}'
```

## Acknowledgments

We thank the security community. Reports that lead to fixes will be credited here:

*(hall of fame — empty until first disclosure)*
