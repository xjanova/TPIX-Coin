/// TPIX Wallet — สเตคมาสเตอร์โหนดกับสัญญา NodeRegistryV2 บน TPIX Chain
///
/// หลักคิด:
///   - TPIX เป็นเหรียญหลักของเชน → สเตค = ส่ง msg.value ไปกับ registerNode()
///     ไม่มี approve แบบ ERC-20
///   - ที่อยู่สัญญามาจากเว็บ (`/api/v1/masternode/config`) แต่ "ไม่เชื่อเว็บอย่างเดียว":
///     ต้อง chain_id = 4289 และ keccak256(eth_getCode) ต้องตรงกับ bytecode ที่ตรึงไว้ในแอป
///     ([knownRegistryCodeHashes]) ก่อนจะยอมให้กดเขียนธุรกรรม — และตรวจซ้ำก่อนเขียนทุกครั้ง
///     (ถ้าเว็บโดนแก้/ตอบผิด ผู้ใช้ต้องไม่ส่งเงินไปที่อยู่ที่ไม่มีสัญญา หรือสัญญาปลอมที่ตอบ ABI เหมือนกัน)
///   - RPC ใช้ RpcClient.tpix ของแอปเอง (หลัก+สำรอง) ไม่ใช้ rpc_url ที่เว็บส่งมา
///   - ★ tier ที่ส่งเข้าสัญญาคือเลข enum (Guardian=0, Sentinel=1, Light=2, Validator=3)
///     ไม่ใช่ลำดับการ์ดบนจอ — เว็บเคยพลาดส่งลำดับการ์ดไปแล้วครั้งหนึ่ง
///
/// ส่วนนี้เป็น Dart ล้วน (ไม่มี widget) เพื่อให้เทสต์การเข้ารหัส ABI + เงื่อนไขปุ่มได้ตรงๆ
///
/// Developed by Xman Studio
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/crypto.dart' show bytesToHex, hexToBytes, keccak256;
import 'package:web3dart/web3dart.dart';

import 'rpc_client.dart';

// ================================================================
// ชนิดข้อมูล
// ================================================================

/// ระดับโหนด — [id] คือค่า enum ในสัญญา (ห้ามใช้ index ของลิสต์บนจอแทน)
enum MnTier {
  guardian(0, 'Guardian'),
  sentinel(1, 'Sentinel'),
  light(2, 'Light'),
  validator(3, 'Validator');

  const MnTier(this.id, this.label);

  /// ค่า uint8 ที่ส่งเข้า registerNode / getTierInfo
  final int id;

  /// ชื่อเฉพาะ — ใช้เหมือนกันทั้งไทยและอังกฤษ (ตรงกับเว็บ)
  final String label;

  static MnTier? fromId(int id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// สถานะโหนด — ตรงกับ enum NodeStatus ในสัญญา
/// [unknown] = ค่าที่แอปรุ่นนี้ไม่รู้จัก (สัญญารุ่นใหม่กว่า) → ปิดทุกปุ่มไว้ก่อน
enum MnStatus {
  inactive(0),
  active(1),
  slashed(2),
  exited(3),
  slashedWithdrawable(4),
  unknown(-1);

  const MnStatus(this.id);
  final int id;

  static MnStatus fromId(int id) {
    for (final s in values) {
      if (s.id == id && s != unknown) return s;
    }
    return unknown;
  }
}

/// สาเหตุที่ปุ่มกดไม่ได้ — UI แปลเป็นข้อความเอง
enum MnBlock {
  paused,
  hasNode,
  claimFirst,

  /// ถอนแล้วยังมีรางวัลค้าง + กองว่าง → สัญญาไม่ให้สเตคใหม่จนกว่ารางวัลค้างจะได้จ่ายครบ
  /// (ไม่มีฟังก์ชันสละรางวัลทิ้ง และ claimRewards() ตอนกองว่างไม่จ่ายอะไรเลย) → ต้องรอเติมกอง
  restakeWaitsForPool,
  unavailable,
  full,
  validatorWebsiteOnly,
  balanceUnknown,
  insufficientBalance,
  nothingToClaim,
  poolEmpty,
  notActive,
  locked,
}

/// เหตุผลที่สัญญาปฏิเสธ (จากข้อความ revert) — แปลเป็นภาษาคนก่อนโชว์
enum MnRevert {
  paused,
  full,
  locked,
  kyc,
  stakeMismatch,
  alreadyRegistered,
  claimFirst,
  endpoint,
  stateChanged,
  insufficientFunds,
  unknown,
}

/// ปัญหาของช่อง endpoint
enum MnEndpointError { empty, tooLong, format, port, local }

/// ความพร้อมของระบบสเตค
enum MnAvailability {
  /// เว็บยังไม่ประกาศที่อยู่สัญญา (ยังไม่ deploy)
  notDeployed,

  /// เว็บบอกว่ามี แต่ตรวจบนเชนไม่ผ่าน (chain id ผิด / ไม่มีโค้ดที่อยู่นั้น) → ห้ามเขียน
  unverified,

  /// ที่อยู่นั้นมีสัญญา แต่ bytecode ไม่ใช่ build ที่แอปรุ่นนี้ตรวจแล้ว → ห้ามเขียน ให้อัปเดตแอป
  unknownCode,

  /// พร้อมใช้
  ready,
}

/// เว็บ/เชนติดต่อไม่ได้ — ให้ผู้ใช้กดลองใหม่ (คนละเรื่องกับ "ยังไม่เปิด")
class MnUnavailableException implements Exception {
  const MnUnavailableException();
  @override
  String toString() => 'Master-node service unavailable';
}

/// สัญญาตอบไม่ตรงกับ ABI ที่แอปรู้จัก (ฟังก์ชันหลักหาย/ข้อมูลเพี้ยน)
class MnContractMismatchException implements Exception {
  const MnContractMismatchException();
  @override
  String toString() => 'Registry contract did not answer as expected';
}

/// bytecode ของสัญญาไม่ตรงกับที่แอปรุ่นนี้ตรึงไว้ — ห้ามเขียนธุรกรรม ให้อัปเดตแอป
class MnUnknownCodeException implements Exception {
  const MnUnknownCodeException();
  @override
  String toString() => 'Registry bytecode is not a build this app has verified';
}

/// ค่าจาก `GET /api/v1/masternode/config`
class MnConfig {
  final String registryAddress;
  final bool registryLive;
  final bool registrationPaused;
  final int? chainId;

  const MnConfig({
    required this.registryAddress,
    required this.registryLive,
    required this.registrationPaused,
    required this.chainId,
  });

  static final _addressRe = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static const _zero = '0x0000000000000000000000000000000000000000';

  /// มีที่อยู่สัญญาที่ใช้ได้ + เว็บบอกว่าเปิดแล้ว
  bool get isPublished =>
      registryLive &&
      _addressRe.hasMatch(registryAddress) &&
      registryAddress.toLowerCase() != _zero;

  /// แปลง JSON — โครงไม่ตรง = null (ผู้เรียกถือว่าเว็บตอบผิด)
  static MnConfig? parse(dynamic body) {
    if (body is! Map || body['success'] != true) return null;
    final data = body['data'];
    if (data is! Map) return null;
    final rawChain = data['chain_id'];
    return MnConfig(
      registryAddress: (data['registry_address'] ?? '').toString().trim(),
      registryLive: data['registry_live'] == true,
      registrationPaused: data['registration_paused'] == true,
      chainId: rawChain is int ? rawChain : int.tryParse('${rawChain ?? ''}'),
    );
  }
}

/// ผลการค้นหาสัญญา
class MnRegistry {
  final MnAvailability availability;

  /// ที่อยู่สัญญา (มีเมื่อ [availability] = ready)
  final String? address;
  final MnConfig? config;

  const MnRegistry(this.availability, {this.address, this.config});
}

/// ข้อมูลระดับโหนดจาก getTierInfo (+ เพดาน APR ถ้าสัญญามี)
class MnTierInfo {
  final MnTier tier;
  final BigInt minStake;
  final BigInt maxNodes; // 0 = ไม่จำกัด
  final BigInt activeNodes;
  final BigInt lockDays;
  final BigInt slashPercentBps;
  final BigInt rewardShareBps;

  /// เพดาน APR (bps) — null = สัญญารุ่นนี้ไม่มีฟังก์ชันนี้/อ่านไม่ได้
  final int? aprCapBps;

  const MnTierInfo({
    required this.tier,
    required this.minStake,
    required this.maxNodes,
    required this.activeNodes,
    required this.lockDays,
    required this.slashPercentBps,
    required this.rewardShareBps,
    this.aprCapBps,
  });

  bool get isConfigured => minStake > BigInt.zero;
  bool get isUnlimited => maxNodes == BigInt.zero;
  bool get isFull => !isUnlimited && activeNodes >= maxNodes;
}

/// ข้อมูลโหนดของกระเป๋าจาก getNodeInfo
class MnNodeInfo {
  final String operator;
  final int tierId;
  final MnStatus status;
  final BigInt stakedAmount;
  final BigInt registeredAt;
  final BigInt unlockAt;
  final BigInt totalRewards;
  final BigInt uptimeBps;
  final String endpoint;
  final BigInt pendingUnclaimed;

  const MnNodeInfo({
    required this.operator,
    required this.tierId,
    required this.status,
    required this.stakedAmount,
    required this.registeredAt,
    required this.unlockAt,
    required this.totalRewards,
    required this.uptimeBps,
    required this.endpoint,
    required this.pendingUnclaimed,
  });

  MnTier? get tier => MnTier.fromId(tierId);

  /// ค่าจากเชนเป็น uint256 — ค่าเพี้ยนเกินช่วงของ DateTime ต้องไม่ทำหน้าจอพัง
  /// (เกินช่วง = ถือว่า "ยังล็อกอยู่อีกนานมาก")
  DateTime get unlockTime {
    const maxSeconds = 8640000000000; // ขอบบนของ DateTime (ms 8.64e15)
    final s = unlockAt > BigInt.from(maxSeconds) ? maxSeconds : unlockAt.toInt();
    return DateTime.fromMillisecondsSinceEpoch(s * 1000);
  }
}

/// ภาพรวมทั้งหมดของหน้าจอ ณ เวลาที่โหลด — ผูกกับกระเป๋า [owner] ใบเดียว
class MnSnapshot {
  final String registry;
  final String owner;
  final bool registrationPaused;

  /// เรียงตาม enum id (index = MnTier.id)
  final List<MnTierInfo> tiers;
  final MnNodeInfo node;

  /// รางวัลที่ได้แล้วแต่ยังไม่จ่าย (รวมที่ยังไม่ settle)
  final BigInt pendingReward;

  /// ที่ claimRewards() จะจ่ายได้จริงตอนนี้ (= min(pending, เงินในกอง))
  final BigInt claimableNow;
  final BigInt availableFunds;

  const MnSnapshot({
    required this.registry,
    required this.owner,
    required this.registrationPaused,
    required this.tiers,
    required this.node,
    required this.pendingReward,
    required this.claimableNow,
    required this.availableFunds,
  });

  MnTierInfo tierInfo(MnTier tier) => tiers[tier.id];

  /// กองรางวัลมีเงินจ่ายจริงไหม (availableRewardFunds > 0)
  /// false = ห้ามโชว์ APR/รายได้เหมือนจะได้จ่ายแน่ — สัญญาจ่ายจากเงินที่ฝากเข้ากองจริงเท่านั้น
  /// (โหลดค่านี้ไม่ได้ = loadSnapshot ล้มทั้งก้อน จึงไม่มีกรณี "ไม่รู้" บนจอ)
  bool get poolFunded => availableFunds > BigInt.zero;

  /// เพดาน APR ที่การ์ดระดับโชว์ได้ — null = ไม่โชว์ (กองยังว่าง หรือสัญญาไม่มีค่านี้)
  int? aprCapToShow(MnTier tier) => poolFunded ? tierInfo(tier).aprCapBps : null;

  /// รางวัลค้างที่ทำให้สเตคใหม่ไม่ได้ (ทั้งกระเป๋า ไม่ขึ้นกับระดับ) — null = ไม่ติด
  ///
  /// สัญญา: registerNode ต้อง nodes[msg.sender].pendingUnclaimed == 0 และไม่มีทางสละรางวัลทิ้ง
  ///   - กองมีเงิน (claimableNow > 0) → กดรับรางวัลได้ (ถ้ากองมีไม่พออาจต้องรับหลายรอบ)
  ///   - กองว่าง → claimRewards() ไม่ revert แต่ไม่จ่ายอะไรเลย = ปุ่มรับรางวัลปิดไว้ถูกแล้ว
  ///     ต้องบอกตรงๆ ว่ารอเติมกอง ไม่ใช่บอก "รับรางวัลก่อน" ทั้งที่กดรับไม่ได้
  MnBlock? get pendingRewardBlock {
    if (node.status != MnStatus.inactive || node.pendingUnclaimed <= BigInt.zero) return null;
    return claimableNow > BigInt.zero ? MnBlock.claimFirst : MnBlock.restakeWaitsForPool;
  }

  /// รางวัลที่จะยังค้างอยู่ถ้าถอนสเตคตอนนี้ (deregisterNode จ่ายได้แค่ min(ที่ค้าง, เงินในกอง))
  /// > 0 = ถอนแล้วกระเป๋านี้สเตคใหม่ไม่ได้ จนกว่ากองจะจ่ายส่วนนี้ครบ
  BigInt get unpaidAfterExit =>
      pendingReward > claimableNow ? pendingReward - claimableNow : BigInt.zero;

  /// มีอะไรให้โชว์ในการ์ด "โหนดของฉัน" (มีโหนด หรือมีรางวัลค้างให้รับ)
  bool get hasNodeCard =>
      node.status != MnStatus.inactive || pendingReward > BigInt.zero;

  /// ลำดับการ์ดบนจอ: สเตคน้อย → มาก, Validator ไว้ท้ายสุด, ระดับที่ยังไม่เปิดไว้หลัง
  /// (ลำดับนี้ใช้ "แสดงผล" เท่านั้น — ส่งเข้าสัญญาใช้ MnTier.id เสมอ)
  List<MnTierInfo> get displayTiers {
    final list = [...tiers];
    int rank(MnTierInfo t) =>
        t.tier == MnTier.validator ? 2 : (t.isConfigured ? 0 : 1);
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.minStake.compareTo(b.minStake);
    });
    return list;
  }

  /// ปุ่ม "สเตค" ของระดับนี้กดได้ไหม — null = กดได้
  /// เรียงเหตุผลจากเรื่องที่แก้ไม่ได้ในแอป → เรื่องที่ผู้ใช้แก้เองได้ (เติมเงิน)
  MnBlock? registerBlock(MnTier tier, BigInt? balanceWei) {
    final info = tierInfo(tier);
    if (tier == MnTier.validator) return MnBlock.validatorWebsiteOnly;
    if (!info.isConfigured) return MnBlock.unavailable;
    if (node.status != MnStatus.inactive) return MnBlock.hasNode;
    // สัญญาเช็ก nodes[msg.sender].pendingUnclaimed == 0 ก่อนให้ลงทะเบียนใหม่
    final pendingBlock = pendingRewardBlock;
    if (pendingBlock != null) return pendingBlock;
    if (registrationPaused) return MnBlock.paused;
    if (info.isFull) return MnBlock.full;
    if (balanceWei == null) return MnBlock.balanceUnknown;
    // TPIX Chain ค่าแก๊ส 0 → ต้องมีแค่ยอดสเตคพอดี
    if (balanceWei < info.minStake) return MnBlock.insufficientBalance;
    return null;
  }

  /// ปุ่ม "รับรางวัล" — กองรางวัลว่าง = รางวัลยังสะสมอยู่ ไม่หาย แค่ยังจ่ายไม่ได้
  MnBlock? claimBlock() {
    if (claimableNow > BigInt.zero) return null;
    if (pendingReward > BigInt.zero) return MnBlock.poolEmpty;
    return MnBlock.nothingToClaim;
  }

  /// ปุ่ม "ถอนสเตค" (deregisterNode) — ต้อง active และพ้นช่วงล็อก
  /// ใช้เวลาเครื่องตัดสินแค่หน้าจอ — ถ้านาฬิกาเครื่องเพี้ยน eth_estimateGas จะเจอ "Still locked" เอง
  MnBlock? unstakeBlock(DateTime now) {
    if (node.status != MnStatus.active) return MnBlock.notActive;
    if (now.isBefore(node.unlockTime)) return MnBlock.locked;
    return null;
  }

  /// ถอนสเตคที่เหลือหลังโดนปรับ — withdrawSlashedStake() รับเฉพาะสถานะ Slashed
  /// (SlashedWithdrawable ไม่เคยถูกตั้งใน V2 และสัญญาจะ revert "Not slashed")
  bool get canWithdrawSlashed =>
      node.status == MnStatus.slashed && node.stakedAmount > BigInt.zero;
}

// ================================================================
// Service
// ================================================================

class MasterNodeService {
  MasterNodeService._();

  static const int chainId = 4289;
  static const configUrl = 'https://tpix.online/api/v1/masternode/config';
  static const websiteUrl = 'https://tpix.online/masternode';

  /// หน้าดาวน์โหลดแอปรุ่นล่าสุด (เมื่อเจอสัญญาที่แอปรุ่นนี้ยังไม่รู้จัก)
  static const downloadUrl = 'https://tpix.online/download';
  static const int maxEndpointLength = 100;
  static const _timeout = Duration(seconds: 10);

  /// เทสต์เปลี่ยนเป็น MockClient ได้
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static RpcClient get _rpc => RpcClient.tpix;

  // ================================================================
  // ตรึง bytecode ของสัญญา
  // ================================================================
  //
  // ที่อยู่สัญญามาจากเว็บ — "มีโค้ด + ตอบ getTierInfo ได้" ไม่พอ: เชนนี้ค่าแก๊ส 0
  // ใครก็ deploy สัญญาปลอมที่ตอบ ABI เหมือนกันได้ฟรี ถ้าเว็บโดนแก้ แอปจะพาเงินสเตคไปเข้าสัญญานั้น
  // NodeRegistryV2 ไม่มี immutable → build เดียวกันได้ hash เดียวกันทุกที่อยู่
  // (ชุดเดียวกับแอป Master Node บนเดสก์ท็อป electron/node-registry.js)
  //
  // ⚠️ deploy build ใหม่ (แก้สัญญา/เปลี่ยน compiler) ต้องเพิ่ม hash ที่นี่และปล่อยแอปรุ่นใหม่
  //    **ก่อน** เปลี่ยนที่อยู่บนเว็บ ไม่งั้นแอปจะปฏิเสธสัญญาใหม่ (ปลอดภัย แต่สเตคไม่ได้)
  //    hash = keccak256(eth_getCode(<ที่อยู่>)) เทียบกับ deployedBytecode ที่ compile จาก commit นั้น

  /// keccak256 ของ runtime bytecode ของ NodeRegistryV2 ที่แอปยอมเขียนธุรกรรมเข้า (ตัวเล็กล้วน)
  static const knownRegistryCodeHashes = <String>{
    // TPIX-Coin 026f5f9 — ตัวที่ deploy จริง 0x9c3662972921705FeFa9E9bF0d91190d7B514A2B
    // (ตรวจซ้ำจาก eth_getCode บน rpc1.tpix.online แล้ว 2026-10-11)
    '0x127979541deea4d4cd468271bea206277d593660634fc78197c5354782c76ce3',
    // TPIX-Coin 7e37dbd — ห้ามแก้ minStake ของระดับที่มีโหนดอยู่ (ถ้า redeploy ตัวนี้)
    '0x8e14ff731f16f502264211c48cc47595f02a4016724f69b67d679c42758765a0',
  };

  /// ที่อยู่ที่ตรวจ bytecode ผ่านแล้วในรอบนี้ (ตัวเล็ก) — โค้ดของสัญญา CREATE ที่ไม่มี selfdestruct
  /// เปลี่ยนไม่ได้ จำไว้ได้ทั้งรอบ ไม่ต้องยิง eth_getCode ซ้ำก่อนเขียนทุกครั้ง
  static final Set<String> _verifiedRegistries = {};

  /// ล้างที่จำไว้ (เทสต์)
  @visibleForTesting
  static void resetVerifiedRegistries() => _verifiedRegistries.clear();

  /// keccak256 ของ bytecode (hex) — null ถ้าไม่ใช่ hex ที่มีเนื้อ
  static String? codeHash(String? code) {
    if (code == null) return null;
    final body = code.startsWith('0x') || code.startsWith('0X') ? code.substring(2) : code;
    if (body.isEmpty || body.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(body)) {
      return null;
    }
    return bytesToHex(keccak256(hexToBytes(body)), include0x: true).toLowerCase();
  }

  /// โค้ดนี้เป็น NodeRegistryV2 build ที่แอปรุ่นนี้ตรวจแล้วไหม
  static bool isKnownRegistryCode(String? code) {
    final h = codeHash(code);
    return h != null && knownRegistryCodeHashes.contains(h);
  }

  /// ด่านก่อนเขียนทุกครั้ง (สเตค/รับรางวัล/ถอน) — ผ่าน = คืนเฉยๆ
  ///
  /// throws [MnUnavailableException] เมื่อถามเชนไม่ได้ (ห้ามถือว่าผ่าน)
  /// throws [MnContractMismatchException] เมื่อโหนดตอบว่าที่อยู่นั้นไม่มีโค้ด
  /// throws [MnUnknownCodeException] เมื่อ bytecode ไม่ตรงกับที่ตรึงไว้
  static Future<void> verifyRegistryCode(String registry) async {
    final key = registry.toLowerCase();
    if (_verifiedRegistries.contains(key)) return;
    final String code;
    try {
      code = await _rpc.getCode(registry);
    } on RpcUnavailableException {
      throw const MnUnavailableException();
    } on RpcException {
      // polygon-edge: ที่อยู่ที่ไม่มีโค้ดตอบ error แทน "0x" — ยังไงก็ไม่ใช่สัญญาที่เขียนเข้าได้
      throw const MnContractMismatchException();
    } on FormatException {
      throw const MnUnavailableException();
    }
    if (!_hasCode(code)) throw const MnContractMismatchException();
    if (!isKnownRegistryCode(code)) throw const MnUnknownCodeException();
    _verifiedRegistries.add(key);
  }

  // ================================================================
  // กันโอนเข้าสัญญาสเตคตรงๆ (หน้าโอน)
  // ================================================================
  //
  // NodeRegistryV2.receive() นับ TPIX ที่โอนเข้าเฉยๆ เป็นเงินบริจาคเข้ากองรางวัล
  // (totalRewardFunded += msg.value) — ไม่ใช่การสเตค และไม่มีฟังก์ชันขอคืน
  // โทเค็น ERC-20 ที่โอนเข้าก็ติดอยู่ถาวร (สัญญาไม่มีทางส่งโทเค็นออก)
  // แอป Master Node บนเดสก์ท็อปบล็อกแบบเดียวกัน (wallet:sendTransaction)

  /// ที่อยู่สัญญาสเตคที่ deploy แล้ว (ตัวเล็ก) — กันได้แม้ยังไม่เคยเปิดหน้ามาสเตอร์โหนดในรอบนี้
  static const knownRegistryAddresses = <String>{
    '0x9c3662972921705fefa9e9bf0d91190d7b514a2b',
  };

  static const _recipientCheckTimeout = Duration(seconds: 5);

  /// ที่อยู่นี้คือสัญญาสเตคที่รู้จักไหม (ไม่ยิงเน็ต): ตัวที่ deploy แล้ว + ตัวที่ตรวจ bytecode ผ่านในรอบนี้
  static bool isKnownRegistryAddress(String address) {
    final a = address.trim().toLowerCase();
    return knownRegistryAddresses.contains(a) || _verifiedRegistries.contains(a);
  }

  /// ปลายทางของหน้าโอนเป็นสัญญาสเตคไหม — รายการที่รู้จักก่อน แล้วค่อยถามเชนว่า bytecode
  /// ตรงกับ build ที่ตรึงไว้ไหม (จับตัวที่ redeploy ใหม่ซึ่งแอปยังไม่รู้ที่อยู่ได้ด้วย)
  ///
  /// ถามเชนไม่ได้/หมดเวลา = false — ด่านนี้กันโอนผิดที่ ไม่ใช่ด่านความปลอดภัยของเงินสเตค
  /// (ที่อยู่ตัวจริงอยู่ในรายการแล้ว และถ้าเน็ตล่ม ตัวธุรกรรมโอนก็ส่งไม่ออกอยู่ดี)
  static Future<bool> isRegistryRecipient(String address) async {
    if (isKnownRegistryAddress(address)) return true;
    try {
      final code = await _rpc.getCode(address.trim()).timeout(_recipientCheckTimeout);
      return isKnownRegistryCode(code);
    } catch (_) {
      // รวม polygon-edge ที่ตอบ error กับกระเป๋าธรรมดาที่มียอด ("unable to fetch code")
      return false;
    }
  }

  /// "0x" / ศูนย์ล้วน = ไม่มีโค้ด
  static bool _hasCode(String code) {
    final body = code.startsWith('0x') ? code.substring(2) : code;
    return body.isNotEmpty && !RegExp(r'^0*$').hasMatch(body);
  }

  // ── ABI (JSON ของ NodeRegistryV2 เฉพาะฟังก์ชันที่แอปใช้) ──
  static const _abiJson = '''
[
 {"type":"function","name":"registerNode","stateMutability":"payable","inputs":[{"name":"_tier","type":"uint8"},{"name":"_endpoint","type":"string"}],"outputs":[]},
 {"type":"function","name":"deregisterNode","stateMutability":"nonpayable","inputs":[],"outputs":[]},
 {"type":"function","name":"claimRewards","stateMutability":"nonpayable","inputs":[],"outputs":[]},
 {"type":"function","name":"withdrawSlashedStake","stateMutability":"nonpayable","inputs":[],"outputs":[]},
 {"type":"function","name":"pendingReward","stateMutability":"view","inputs":[{"name":"","type":"address"}],"outputs":[{"name":"","type":"uint256"}]},
 {"type":"function","name":"claimableNow","stateMutability":"view","inputs":[{"name":"","type":"address"}],"outputs":[{"name":"","type":"uint256"}]},
 {"type":"function","name":"availableRewardFunds","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"uint256"}]},
 {"type":"function","name":"registrationPaused","stateMutability":"view","inputs":[],"outputs":[{"name":"","type":"bool"}]},
 {"type":"function","name":"tierAprCapBps","stateMutability":"view","inputs":[{"name":"","type":"uint8"}],"outputs":[{"name":"","type":"uint256"}]},
 {"type":"function","name":"getTierInfo","stateMutability":"view","inputs":[{"name":"","type":"uint8"}],"outputs":[{"name":"","type":"tuple","components":[
   {"name":"minStake","type":"uint256"},{"name":"maxNodes","type":"uint256"},{"name":"activeNodes","type":"uint256"},
   {"name":"lockDays","type":"uint256"},{"name":"slashPercent","type":"uint256"},{"name":"rewardShare","type":"uint256"}]}]},
 {"type":"function","name":"getNodeInfo","stateMutability":"view","inputs":[{"name":"","type":"address"}],"outputs":[{"name":"","type":"tuple","components":[
   {"name":"operator","type":"address"},{"name":"tier","type":"uint8"},{"name":"status","type":"uint8"},
   {"name":"stakedAmount","type":"uint256"},{"name":"registeredAt","type":"uint256"},{"name":"unlockAt","type":"uint256"},
   {"name":"lastRewardAt","type":"uint256"},{"name":"totalRewards","type":"uint256"},{"name":"uptime","type":"uint256"},
   {"name":"nodeId","type":"bytes32"},{"name":"endpoint","type":"string"},{"name":"rewardDebt","type":"uint256"},
   {"name":"pendingUnclaimed","type":"uint256"}]}]}
]
''';

  static final ContractAbi _abi = ContractAbi.fromJson(_abiJson, 'NodeRegistryV2');

  static ContractFunction _fn(String name) =>
      _abi.functions.firstWhere((f) => f.name == name);

  // ================================================================
  // Calldata สำหรับเขียน
  // ================================================================

  /// registerNode(uint8 tier, string endpoint) — ต้องส่ง value = minStake ของระดับนั้นพอดี
  static Uint8List encodeRegister(MnTier tier, String endpoint) =>
      _fn('registerNode').encodeCall([BigInt.from(tier.id), endpoint]);

  static Uint8List encodeDeregister() => _fn('deregisterNode').encodeCall(const []);
  static Uint8List encodeClaim() => _fn('claimRewards').encodeCall(const []);
  static Uint8List encodeWithdrawSlashed() =>
      _fn('withdrawSlashedStake').encodeCall(const []);

  // ================================================================
  // ค่าแก๊ส
  // ================================================================
  //
  // วัดจริงจากสัญญา (ทีมสัญญา): registerNode ครั้งแรก ~367k (endpoint 17 ตัว) ถึง ~430k
  // (100 ตัว), claimRewards ~158k, deregisterNode ~114k
  // ค่าแก๊สเชนนี้เป็น 0 → ตั้งเผื่อเยอะไม่เสียเงิน แต่ตั้งน้อยไป = ธุรกรรม out-of-gas เสียเปล่า
  // เลยใช้ ประเมินจริง ×1.3 แต่ไม่ต่ำกว่าพื้นของแต่ละฟังก์ชัน

  static const gasFloorRegister = 600000;
  static const gasFloorClaim = 250000;
  static const gasFloorDeregister = 250000;
  static const gasFloorWithdrawSlashed = 200000;

  /// max(ประเมิน×1.3 ปัดขึ้น, พื้น)
  static int gasLimit(int estimated, int floor) {
    final padded = (estimated * 13 + 9) ~/ 10;
    return padded > floor ? padded : floor;
  }

  /// eth_estimateGas = ด่านตรวจก่อนถาม PIN — ถ้าสัญญาจะ revert ได้ข้อความเหตุผลกลับมาเลย
  /// (throws [RpcException] พร้อมข้อความ revert / [RpcUnavailableException] เมื่อเน็ตหลุด)
  static Future<int> estimateGas({
    required String registry,
    required String from,
    required Uint8List data,
    BigInt? value,
  }) async {
    final params = <String, String>{
      'from': from,
      'to': registry,
      if (value != null && value > BigInt.zero) 'value': '0x${value.toRadixString(16)}',
      'data': _hexArg(data),
    };
    final result = await _rpc.call('eth_estimateGas', [params]);
    return RpcClient.parseQuantity(result).toInt();
  }

  // ================================================================
  // ถอดค่าที่อ่านจากเชน (แยกไว้ให้เทสต์ด้วยข้อมูลจริงจาก ethers ได้)
  // ================================================================

  static List<dynamic> _decode(String fn, String? hex) {
    // "0x" = ไม่มีโค้ด/ไม่มีฟังก์ชันนี้ → ถือว่าสัญญาไม่ตรงกับที่รู้จัก
    if (hex == null || hex.length <= 2) throw const MnContractMismatchException();
    try {
      return _fn(fn).decodeReturnValues(hex);
    } catch (_) {
      throw const MnContractMismatchException();
    }
  }

  static BigInt decodeUint(String fn, String? hex) => _decode(fn, hex).first as BigInt;

  static MnTierInfo decodeTierInfo(MnTier tier, String? hex, {int? aprCapBps}) {
    final t = _decode('getTierInfo', hex).first as List;
    return MnTierInfo(
      tier: tier,
      minStake: t[0] as BigInt,
      maxNodes: t[1] as BigInt,
      activeNodes: t[2] as BigInt,
      lockDays: t[3] as BigInt,
      slashPercentBps: t[4] as BigInt,
      rewardShareBps: t[5] as BigInt,
      aprCapBps: aprCapBps,
    );
  }

  static MnNodeInfo decodeNodeInfo(String? hex) {
    final n = _decode('getNodeInfo', hex).first as List;
    return MnNodeInfo(
      operator: (n[0] as EthereumAddress).hex,
      tierId: (n[1] as BigInt).toInt(),
      status: MnStatus.fromId((n[2] as BigInt).toInt()),
      stakedAmount: n[3] as BigInt,
      registeredAt: n[4] as BigInt,
      unlockAt: n[5] as BigInt,
      totalRewards: n[7] as BigInt,
      uptimeBps: n[8] as BigInt,
      endpoint: n[10] as String,
      pendingUnclaimed: n[12] as BigInt,
    );
  }

  // ================================================================
  // ค้นหา + ตรวจสัญญา
  // ================================================================

  /// อ่าน config จากเว็บ แล้วตรวจบนเชนเองว่าที่อยู่นั้นเป็นสัญญา build ที่แอปรู้จัก
  ///
  /// throws [MnUnavailableException] เมื่อเว็บ/เชนติดต่อไม่ได้ (ให้ผู้ใช้ลองใหม่)
  static Future<MnRegistry> discover() async {
    final config = await fetchConfig();
    if (config == null || !config.isPublished) {
      return MnRegistry(MnAvailability.notDeployed, config: config);
    }
    // เว็บบอกเชนอื่น = ผิดปกติ ห้ามส่งเงิน
    if (config.chainId != chainId) {
      return MnRegistry(MnAvailability.unverified, config: config);
    }
    final String code;
    try {
      code = await _rpc.getCode(config.registryAddress);
    } on RpcUnavailableException {
      throw const MnUnavailableException();
    } on RpcException {
      // ★ polygon-edge (เชน TPIX): ที่อยู่ที่มีบัญชีแต่ไม่มีโค้ด (EOA ที่มียอด) ตอบ error
      //   {"code":-32600,"message":"unable to fetch code"} แทน "0x"
      //   โหนดตอบมาแล้ว = คำตอบจริงของเชน → ถือว่า "ไม่มีสัญญา" ไม่ใช่ "RPC ล่ม"
      return MnRegistry(MnAvailability.unverified, config: config);
    } on FormatException {
      throw const MnUnavailableException();
    }
    if (!_hasCode(code)) {
      return MnRegistry(MnAvailability.unverified, config: config);
    }
    // มีโค้ด แต่ไม่ใช่ build ที่ตรวจแล้ว (สัญญาปลอม หรือ redeploy ที่แอปรุ่นนี้ยังไม่รู้จัก)
    if (!isKnownRegistryCode(code)) {
      return MnRegistry(MnAvailability.unknownCode, config: config);
    }
    _verifiedRegistries.add(config.registryAddress.toLowerCase());
    return MnRegistry(
      MnAvailability.ready,
      address: config.registryAddress,
      config: config,
    );
  }

  /// null = เว็บยังไม่มี endpoint นี้ (404) หรือ success=false → ถือว่ายังไม่เปิด
  /// throws [MnUnavailableException] เมื่อเน็ตหลุด/timeout/5xx/หน้า HTML ของ Cloudflare
  static Future<MnConfig?> fetchConfig() async {
    final client = clientFactory();
    try {
      final res = await client.get(Uri.parse(configUrl), headers: const {
        'Accept': 'application/json',
        // ไม่มี User-Agent = Cloudflare หน้า tpix.online ตอบหน้า HTML บล็อก
        'User-Agent': 'TPIX-Wallet (Flutter)',
      }).timeout(_timeout);
      if (res.statusCode == 404) return null;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw const MnUnavailableException();
      }
      final dynamic body;
      try {
        body = jsonDecode(res.body);
      } on FormatException {
        throw const MnUnavailableException();
      }
      if (body is! Map) throw const MnUnavailableException();
      return MnConfig.parse(body);
    } on MnUnavailableException {
      rethrow;
    } catch (e) {
      debugPrint('MasterNodeService.fetchConfig: ${e.runtimeType}');
      throw const MnUnavailableException();
    } finally {
      client.close();
    }
  }

  // ================================================================
  // อ่านสถานะทั้งหมดของหน้าจอ
  // ================================================================

  static String _hexArg(Uint8List data) => bytesToHex(data, include0x: true);

  static Future<String?> _call(String registry, String fn, List<dynamic> args) =>
      _rpc.ethCall(registry, _hexArg(_fn(fn).encodeCall(args)));

  /// ฟังก์ชันเสริมของสัญญารุ่นใหม่ — สัญญารุ่นเก่าไม่มี = revert → คืน null (ไม่ทำทั้งหน้าพัง)
  static Future<String?> _optionalCall(
      String registry, String fn, List<dynamic> args) async {
    try {
      final r = await _call(registry, fn, args);
      return r == null || r.length <= 2 ? null : r;
    } on RpcException {
      return null;
    }
  }

  /// โหลดทุกอย่างพร้อมกัน — ฟังก์ชันหลักล้ม = throw ทั้งก้อน (ห้ามโชว์ข้อมูลครึ่งๆ กลางๆ)
  ///
  /// [configPaused] ใช้แทนเมื่อสัญญาไม่มี registrationPaused()
  static Future<MnSnapshot> loadSnapshot({
    required String registry,
    required String owner,
    bool configPaused = false,
  }) async {
    final ownerAddr = EthereumAddress.fromHex(owner);
    try {
      final tierCalls = [
        for (final t in MnTier.values) _call(registry, 'getTierInfo', [BigInt.from(t.id)]),
      ];
      final aprCalls = [
        for (final t in MnTier.values)
          _optionalCall(registry, 'tierAprCapBps', [BigInt.from(t.id)]),
      ];
      final results = await Future.wait<String?>([
        ...tierCalls, // 0..3
        ...aprCalls, // 4..7
        _optionalCall(registry, 'registrationPaused', const []), // 8
        _call(registry, 'getNodeInfo', [ownerAddr]), // 9
        _call(registry, 'pendingReward', [ownerAddr]), // 10
        _call(registry, 'claimableNow', [ownerAddr]), // 11
        _call(registry, 'availableRewardFunds', const []), // 12
      ]);

      final tiers = [
        for (final t in MnTier.values)
          decodeTierInfo(
            t,
            results[t.id],
            aprCapBps: _safeAprBps(results[4 + t.id]),
          ),
      ];
      final pausedHex = results[8];
      bool paused = configPaused;
      if (pausedHex != null) {
        try {
          paused = _decode('registrationPaused', pausedHex).first as bool;
        } on MnContractMismatchException {
          paused = configPaused;
        }
      }
      return MnSnapshot(
        registry: registry,
        owner: owner,
        registrationPaused: paused,
        tiers: tiers,
        node: decodeNodeInfo(results[9]),
        pendingReward: decodeUint('pendingReward', results[10]),
        claimableNow: decodeUint('claimableNow', results[11]),
        availableFunds: decodeUint('availableRewardFunds', results[12]),
      );
    } on RpcUnavailableException {
      throw const MnUnavailableException();
    } on RpcException {
      // ฟังก์ชันหลัก revert = สัญญาไม่ใช่ตัวที่แอปรู้จัก
      throw const MnContractMismatchException();
    }
  }

  static int? _safeAprBps(String? hex) {
    if (hex == null) return null;
    try {
      final v = decodeUint('tierAprCapBps', hex);
      // เกิน 1,000,000% = ค่าเพี้ยน ไม่โชว์
      return v > BigInt.from(100000000) ? null : v.toInt();
    } on MnContractMismatchException {
      return null;
    }
  }

  // ================================================================
  // ตรวจ endpoint (host:port)
  // ================================================================

  /// null = ผ่าน — สัญญานับความยาวเป็นไบต์ จึงรับเฉพาะ ASCII (1 ตัว = 1 ไบต์)
  static MnEndpointError? validateEndpoint(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return MnEndpointError.empty;
    if (s.length > maxEndpointLength) return MnEndpointError.tooLong;

    String host;
    String port;
    final v6 = RegExp(r'^\[([0-9a-fA-F:.]+)\]:([0-9]+)$').firstMatch(s);
    if (v6 != null) {
      host = v6.group(1)!;
      port = v6.group(2)!;
      if (!host.contains(':')) return MnEndpointError.format;
      if (host == '::1' || host == '::') return MnEndpointError.local;
    } else {
      final m = RegExp(r'^([A-Za-z0-9.-]+):([0-9]+)$').firstMatch(s);
      if (m == null) return MnEndpointError.format;
      host = m.group(1)!;
      port = m.group(2)!;
      if (!_isHostname(host)) return MnEndpointError.format;
      final lower = host.toLowerCase();
      if (lower == 'localhost' ||
          lower.endsWith('.localhost') ||
          lower == '0.0.0.0' ||
          lower.startsWith('127.')) {
        // เครือข่ายเข้าไม่ถึง = สเตคไปก็ไม่ได้อัปไทม์
        return MnEndpointError.local;
      }
    }
    final p = int.tryParse(port);
    if (port.length > 5 || p == null || p < 1 || p > 65535) {
      return MnEndpointError.port;
    }
    return null;
  }

  static bool _isHostname(String host) {
    if (host.length > 253 || host.startsWith('.') || host.endsWith('.')) return false;
    final labels = host.split('.');
    // ตัวเลขล้วนทุกช่วง = ต้องเป็น IPv4 ที่ถูกต้อง
    if (labels.every((l) => RegExp(r'^[0-9]+$').hasMatch(l))) {
      if (labels.length != 4) return false;
      return labels.every((l) {
        final n = int.tryParse(l);
        return n != null && n >= 0 && n <= 255 && (l.length == 1 || !l.startsWith('0'));
      });
    }
    final label = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
    return labels.every(label.hasMatch);
  }

  // ================================================================
  // แปลงข้อความ revert
  // ================================================================

  static MnRevert classifyRevert(String message) {
    final m = message.toLowerCase();
    if (m.contains('registration paused')) return MnRevert.paused;
    if (m.contains('tier full')) return MnRevert.full;
    if (m.contains('still locked')) return MnRevert.locked;
    if (m.contains('kyc')) return MnRevert.kyc;
    if (m.contains('insufficient stake') || m.contains('stake must equal')) {
      return MnRevert.stakeMismatch;
    }
    if (m.contains('already registered')) return MnRevert.alreadyRegistered;
    if (m.contains('claim pending rewards first')) return MnRevert.claimFirst;
    if (m.contains('endpoint')) return MnRevert.endpoint;
    if (m.contains('not active') ||
        m.contains('not slashed') ||
        m.contains('nothing to withdraw')) {
      return MnRevert.stateChanged;
    }
    if (m.contains('insufficient funds') || m.contains('exceeds balance')) {
      return MnRevert.insufficientFunds;
    }
    return MnRevert.unknown;
  }

  // ================================================================
  // แสดงผลตัวเลข (BigInt ล้วน ไม่ผ่าน double)
  // ================================================================

  static final _wei = BigInt.from(10).pow(18);

  /// wei → "1,234,567.8912" — ตัดทศนิยมทิ้ง (ไม่ปัดขึ้น) ไม่ให้ดูเหมือนมีมากกว่าจริง
  /// [maxDecimals] = 18 ใช้กับหน้ายืนยัน (ต้องเป็นตัวเลขจริงทุกหลัก)
  static String formatTpix(BigInt wei, {int maxDecimals = 4}) {
    final negative = wei.isNegative;
    final abs = wei.abs();
    final whole = (abs ~/ _wei).toString();
    var frac = (abs % _wei).toString().padLeft(18, '0');
    frac = frac.substring(0, maxDecimals.clamp(0, 18)).replaceFirst(RegExp(r'0+$'), '');
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final body = frac.isEmpty ? grouped : '$grouped.$frac';
    return negative ? '-$body' : body;
  }

  /// bps → "12%" / "12.5%"
  static String formatBps(int bps) {
    final whole = bps ~/ 100;
    final rem = bps % 100;
    if (rem == 0) return '$whole%';
    final frac = rem.toString().padLeft(2, '0').replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$frac%';
  }
}
