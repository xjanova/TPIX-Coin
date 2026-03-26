# CLAUDE.md — TPIX Chain Project Guidelines

## Project Overview
TPIX Chain: EVM blockchain (Polygon Edge/IBFT2, Chain ID 4289, zero gas, 2s blocks).
Products: Flutter wallet (Android/iOS), Electron masternode UI (Windows), Hardhat smart contracts, Uniswap V2 DEX.

## Code Review Protocol: Scenario-Based Testing

**Every code review MUST simulate real-world usage scenarios before approving.**

### Mandatory Checklist

Before marking any feature code as "done", walk through these scenario categories:

#### 1. State Management Scenarios
- [ ] **StatefulBuilder trap**: Any `StatefulBuilder` that declares variables inside `builder:` will reset them on every rebuild. Extract to a proper `StatefulWidget` if state must persist across rebuilds.
- [ ] **setState after async**: Every `await` followed by `setState` must check `if (!mounted) return` first.
- [ ] **Loading state flash**: Avoid showing full-screen loading spinners for incremental updates. Use `showSpinner` flags to distinguish initial load from refresh.

#### 2. User Flow Scenarios
- [ ] **First-time user**: Screen with no data — does it look correct and guide the user?
- [ ] **Returning user**: User already has data — are fields pre-filled? Is there an overwrite warning?
- [ ] **Fat-finger protection**: Destructive actions (delete, overwrite) require confirmation dialogs.
- [ ] **Error messages**: Never show raw `Exception: ...` to users. Strip prefixes, use localized messages.
- [ ] **Rapid taps**: Can the user double-tap a button and trigger duplicate operations?

#### 3. Security Scenarios
- [ ] **Rate limiting scope**: Self-tests and diagnostics must NOT count against security rate limits.
- [ ] **Multi-wallet isolation**: Identity/security data — is it per-wallet or global? Document which and why.
- [ ] **Ternary logic in failure branches**: When you're inside `if (!x && !y)`, don't check `x` in the ternary — it's always false there. Check the actual discriminator.

#### 4. Cross-Device / Cross-Platform Scenarios
- [ ] **Float-to-string consistency**: Never use `double.toString()` for values that will be hashed or compared across devices. Use `toStringAsFixed(n)`.
- [ ] **GPS variance**: GPS readings vary ±10m per reading. Grid-hash with neighbor checking handles this.
- [ ] **Storage key collisions**: If the app supports multiple wallets, storage keys must include wallet identifier or be documented as intentionally global.

#### 5. Resource Management
- [ ] **TextEditingController disposal**: Controllers created in dialogs/bottom sheets must be disposed or the dialog must handle cleanup.
- [ ] **AnimationController disposal**: All animation controllers created in `initState` must be disposed in `dispose()`.
- [ ] **Subscription cleanup**: Stream subscriptions must be cancelled in `dispose()`.

### How to Apply

When reviewing code, mentally execute these scenarios:
```
For each screen/feature:
  1. New user opens it (empty state)
  2. User fills all fields and saves (happy path)
  3. User has existing data and re-opens (edit mode)
  4. User does something wrong (error handling)
  5. User cancels mid-operation (cleanup)
  6. User loses network/GPS during operation (timeout)
  7. User switches wallet/language during operation
  8. User rapid-taps buttons (debounce)
  9. Screen is disposed during async operation (mounted check)
  10. Data is accessed from a different device (consistency)
```

## Tech Stack
- **Wallet**: Flutter 3.38+, Dart 3.x, Provider state management
- **Masternode UI**: Electron, Node.js 20+, SQLite
- **Contracts**: Hardhat, Solidity 0.8.20, ethers v6
- **CI/CD**: GitHub Actions — `v*` tag triggers builds

## Conventions
- Commit messages: `type: description` (feat, fix, chore, docs)
- Thai + English bilingual UI (LocaleProvider with `l.t('key')`)
- Dark theme with gradients (AppTheme.primary, AppTheme.accent)
- SynthService for UI sounds (playTap, playSendSuccess, playError)
- FlutterSecureStorage with AndroidOptions(encryptedSharedPreferences: true)
