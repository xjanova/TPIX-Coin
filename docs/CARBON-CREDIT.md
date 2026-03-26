# TPIX Chain — Carbon Credit System

> **Transparent Carbon Credit Trading on Blockchain with IoT Verification**
> Developed by Xman Studio | [tpix.online/carbon-credits](https://tpix.online/carbon-credits)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Why Blockchain for Carbon Credits?](#2-why-blockchain-for-carbon-credits)
3. [How It Works](#3-how-it-works)
4. [Supported Standards](#4-supported-standards)
5. [Project Types](#5-project-types)
6. [Marketplace](#6-marketplace)
7. [Blockchain Architecture](#7-blockchain-architecture)
8. [Credit Tokenomics](#8-credit-tokenomics)
9. [API Reference](#9-api-reference)
10. [Mobile App Integration](#10-mobile-app-integration)
11. [Roadmap](#11-roadmap)
12. [Legal & Compliance](#12-legal--compliance)

---

## 1. Overview

TPIX Chain's Carbon Credit system enables transparent, verifiable trading of carbon credits using blockchain technology combined with IoT sensor verification. By tokenizing carbon credits on TPIX Chain, we eliminate double-counting, ensure transparent ownership, and enable fractional trading — all with zero gas fees.

### Key Features

- **Verified Credits** — Only credits verified by international standards (VCS, Gold Standard, CDM, ACR) are accepted
- **IoT Integration** — Real-time sensor data feeds into verification oracles for ongoing monitoring
- **Zero Gas Fees** — Trade and retire credits without transaction costs on TPIX Chain
- **Fractional Trading** — Buy as little as 0.001 tCO₂e (ton of CO₂ equivalent)
- **Transparent Audit Trail** — Every issuance, transfer, and retirement recorded on blockchain
- **Bilingual** — Full Thai and English support

---

## 2. Why Blockchain for Carbon Credits?

### Problems in Traditional Carbon Markets

| Problem | Impact |
|---------|--------|
| **Double Counting** | Same credit sold to multiple buyers |
| **Lack of Transparency** | Difficult to verify credit authenticity |
| **High Intermediary Costs** | Brokers and registries take 15-30% fees |
| **Slow Settlement** | Weeks to months for credit transfer |
| **Limited Access** | Only large corporations can participate |
| **Greenwashing** | Claims without verifiable proof |

### TPIX Chain Solutions

| Solution | How |
|----------|-----|
| **Immutable Ledger** | Each credit is a unique on-chain token — impossible to double-spend |
| **Public Verification** | Anyone can verify credit origin and ownership on Block Explorer |
| **Direct Trading** | P2P marketplace with only 2% platform fee |
| **Instant Settlement** | 2-second block time, credits transfer immediately |
| **Fractional Ownership** | Buy 0.001 tCO₂e — accessible to individuals and SMEs |
| **On-Chain Proof** | Retirement certificates are permanent, verifiable NFTs |

---

## 3. How It Works

### End-to-End Flow

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Project    │───→│  Verification │───→│   Issuance  │
│ Registration │    │  (IoT + Audit)│    │ (Tokenize)  │
└─────────────┘    └──────────────┘    └──────┬──────┘
                                              │
┌─────────────┐    ┌──────────────┐    ┌──────▼──────┐
│ Certificate  │←───│  Retirement   │←───│ Marketplace │
│  (On-chain)  │    │  (Burn Token) │    │  (Trading)  │
└─────────────┘    └──────────────┘    └─────────────┘
```

### Step-by-Step

1. **Project Registration** — Project developer submits details (location, type, methodology, expected reduction)
2. **Verification** — Third-party auditor + IoT sensors verify actual carbon reduction
3. **Credit Issuance** — Verified credits minted as ERC-721 tokens on TPIX Chain
4. **Marketplace Trading** — Credits listed on `tpix.online/carbon-credits` for buying/selling
5. **Retirement** — When used for offsetting, credits are permanently burned on-chain
6. **Certificate** — Immutable on-chain proof of retirement for compliance and reporting

---

## 4. Supported Standards

### VCS (Verified Carbon Standard)

- **Managed by**: Verra
- **Coverage**: Global — largest voluntary carbon market
- **Methodology**: 100+ approved methodologies
- **Projects**: Renewable energy, forestry, agriculture, waste management
- **Registry**: [verra.org](https://verra.org)

### Gold Standard

- **Managed by**: Gold Standard Foundation
- **Coverage**: Global — premium market with SDG co-benefits
- **Methodology**: Must demonstrate contribution to at least 3 UN SDGs
- **Projects**: Clean energy, water, health, community development
- **Registry**: [goldstandard.org](https://goldstandard.org)

### CDM (Clean Development Mechanism)

- **Managed by**: UNFCCC (United Nations)
- **Coverage**: Developing nations under Kyoto Protocol
- **Methodology**: Generates CERs (Certified Emission Reductions)
- **Projects**: Industrial efficiency, renewable energy, waste management
- **Registry**: [cdm.unfccc.int](https://cdm.unfccc.int)

### ACR (American Carbon Registry)

- **Managed by**: Winrock International
- **Coverage**: North America focus
- **Methodology**: Forestry, wetlands, livestock, industrial
- **Projects**: US-based reforestation, methane capture, soil carbon
- **Registry**: [americancarbonregistry.org](https://americancarbonregistry.org)

---

## 5. Project Types

### Renewable Energy
Solar farms, wind turbines, biomass plants — displacing fossil fuel electricity generation.

### Reforestation & Afforestation
Tree planting and forest restoration — sequestering CO₂ through natural growth.

### Energy Efficiency
Industrial process optimization, building retrofits, LED upgrades — reducing energy consumption.

### Methane Capture
Landfill gas recovery, livestock methane digesters — capturing potent greenhouse gases.

### Clean Cookstoves
Replacing traditional biomass cooking with efficient stoves — reducing emissions and improving health.

### Blue Carbon
Mangrove restoration, seagrass protection, coastal wetlands — marine ecosystem carbon sequestration.

### Waste Management
Recycling programs, composting, waste-to-energy — diverting waste from landfills.

---

## 6. Marketplace

### Features

| Feature | Description |
|---------|-------------|
| **Real-Time Pricing** | Live credit prices by standard and project type |
| **Project Browser** | Filter by standard, type, location, vintage |
| **Portfolio Dashboard** | Track owned credits, retirement history, ROI |
| **Bulk Trading** | OTC desk for large volume purchases (>10,000 tCO₂e) |
| **Auto-Retirement** | Schedule automatic credit retirement for ongoing offsetting |
| **API Access** | REST API for programmatic trading and integration |

### Fee Structure

| Action | Fee |
|--------|-----|
| Buy/Sell Credits | 2% platform fee |
| Credit Retirement | Free |
| Certificate Download | Free |
| API Access | Free (rate limited to 100 req/min) |

---

## 7. Blockchain Architecture

### Hybrid On-Chain / Off-Chain Model

```
On-Chain (TPIX Chain):              Off-Chain (IPFS + Database):
├── Credit ownership (ERC-721)      ├── Project documentation
├── Transfer history                ├── Verification reports
├── Retirement records              ├── IoT sensor data
├── Certificate NFTs                ├── Satellite imagery
└── Audit trail                     └── Detailed metadata
```

### Why Hybrid?

- **Cost** — Storing large documents on-chain is expensive (even with zero gas, storage grows)
- **Privacy** — Some verification data contains sensitive business information
- **Performance** — IoT sensor data volume would overwhelm on-chain storage
- **Flexibility** — Off-chain data can be updated without new transactions

### Credit Token (ERC-721)

Each carbon credit batch is represented as an ERC-721 NFT containing:

```json
{
  "tokenId": 1234,
  "standard": "VCS",
  "projectId": "VCS-2345",
  "vintage": 2025,
  "quantity_tco2e": 100.0,
  "projectType": "renewable_energy",
  "country": "TH",
  "metadataURI": "ipfs://Qm...",
  "issuedAt": "2025-06-15T00:00:00Z",
  "retired": false
}
```

---

## 8. Credit Tokenomics

### Fee Distribution

| Fee Source | Distribution |
|-----------|-------------|
| 2% Platform Fee | 50% Treasury, 30% Stakers, 20% Burned |

### Credit Lifecycle

```
Minted → Active (tradeable) → Retired (burned) → Certificate (NFT)
```

- **Minted**: Credits issued after verification, assigned to project developer
- **Active**: Listed on marketplace, can be bought/sold/transferred
- **Retired**: Permanently burned for carbon offsetting — irreversible
- **Certificate**: ERC-721 retirement certificate minted to the retiring party

---

## 9. API Reference

### Base URL

```
https://tpix.online/api/v1/carbon-credits
```

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/projects` | List all active carbon credit projects |
| `GET` | `/projects/{id}` | Get project details |
| `GET` | `/credits` | List available credits for trading |
| `GET` | `/credits/{id}` | Get credit details and history |
| `POST` | `/credits/{id}/retire` | Retire credits (requires wallet signature) |
| `GET` | `/certificates` | List retirement certificates |
| `GET` | `/stats` | Market statistics and aggregated data |

### Example Response

```json
{
  "success": true,
  "data": {
    "id": 1234,
    "standard": "VCS",
    "project_name": "Chiang Mai Solar Farm",
    "vintage": 2025,
    "quantity_available": 5000.0,
    "price_per_tco2e": 12.50,
    "currency": "TPIX",
    "country": "TH",
    "project_type": "renewable_energy",
    "verified_at": "2025-06-15T00:00:00Z"
  }
}
```

---

## 10. Mobile App Integration

The TPIX Wallet mobile app includes carbon credit features:

- **Browse Projects** — View available carbon credit projects
- **Buy Credits** — Purchase credits directly from wallet
- **View Portfolio** — Track owned carbon credits
- **Retire Credits** — Offset your carbon footprint
- **Share Certificate** — Share retirement proof on social media
- **QR Verification** — Scan product QR to see carbon offset status

---

## 11. Roadmap

| Phase | Period | Status | Milestones |
|-------|--------|--------|------------|
| **Foundation** | Q1 2025 | Done | Architecture, smart contracts, API design |
| **MVP** | Q2 2025 | Done | Marketplace, VCS/Gold Standard support, basic trading |
| **IoT Integration** | Q3 2025 | Done | Sensor oracle, real-time verification |
| **Enterprise** | Q1-Q2 2026 | In Progress | Bulk trading, API v2, compliance reporting, CDM/ACR support |
| **Global** | Q3-Q4 2026 | Planned | International partnerships, cross-chain credits, satellite verification |

---

## 12. Legal & Compliance

- Carbon credits listed on TPIX Chain are verified by internationally recognized standards (VCS, Gold Standard, CDM, ACR)
- TPIX Chain does not guarantee the environmental impact of any project — verification is performed by independent third-party auditors
- Trading carbon credits involves risk — prices may fluctuate based on market conditions
- Retirement certificates are for voluntary carbon offsetting and may not satisfy all regulatory compliance requirements
- Users are responsible for verifying project legitimacy through the standard's official registry
- TPIX Chain complies with Thai digital asset regulations for token trading

---

## Links

| Resource | URL |
|----------|-----|
| **Carbon Credit Marketplace** | [tpix.online/carbon-credits](https://tpix.online/carbon-credits) |
| **Carbon Credit Whitepaper** | [tpix.online/carbon-credits/whitepaper](https://tpix.online/carbon-credits/whitepaper) |
| **Block Explorer** | [explorer.tpix.online](https://explorer.tpix.online) |
| **API Documentation** | [tpix.online/api/v1/carbon-credits](https://tpix.online/api/v1/carbon-credits) |
| **TPIX Chain Whitepaper** | [docs/WHITEPAPER.md](WHITEPAPER.md) |

---

<p align="center">
  <strong>TPIX Chain Carbon Credit System</strong><br/>
  Last updated: March 2026<br/>
  Developed by <a href="https://xmanstudio.com">Xman Studio</a>
</p>
