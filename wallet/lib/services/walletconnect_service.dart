import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:tpix_wallet/models/chain_config.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/services/app_return.dart';
import 'package:tpix_wallet/services/rpc_client.dart' show RpcException, RpcUnavailableException;
import 'package:tpix_wallet/services/wallet_service.dart' show InsufficientGasException, WalletChangedException;
import 'package:tpix_wallet/services/wc_deep_link.dart';
import 'package:tpix_wallet/services/wc_request_rules.dart';

/// WalletConnect v2 service — manages dApp connections for TPIX Wallet.
///
/// Flow:
/// 1. dApp shows QR code / deep link (tpixwallet://wc?uri=… จากเว็บบนมือถือ)
/// 2. User scans → [pair] creates pairing (รอ init ให้เสร็จก่อนถ้าเปิดแอปเย็นจากลิงก์)
/// 3. dApp sends SessionProposal → เข้าคิว [pendingProposal] (ตัวหน้าสุดโชว์บนการ์ด)
/// 4. User approves → wallet responds with approved namespaces
/// 5. dApp sends requests (personal_sign, eth_sendTransaction) → เข้าคิว [pendingRequest]
///    สลับ/เพิ่มเชน + คำขอที่ตอบได้เลย (params เสีย / ขอกระเป๋าอื่น) ตอบเองไม่ขึ้นการ์ด
/// 6. Wallet signs and responds — ถ้ามาจากลิงก์ของเบราว์เซอร์ ส่งเสร็จแล้วพากลับเบราว์เซอร์ ([WcVisit])
class WalletConnectService extends ChangeNotifier {
  /// [moveToBack] / [clock] ให้เทสต์ใส่ของปลอมได้ — แอปจริงใช้ค่าเริ่มต้น
  WalletConnectService({Future<bool> Function()? moveToBack, DateTime Function()? clock})
      : _moveToBack = moveToBack ?? AppReturn.moveToBack,
        _clock = clock ?? DateTime.now;

  // ================================================================
  //  Constants
  // ================================================================

  /// Register at https://cloud.reown.com to get your project ID.
  /// Replace this placeholder before release.
  static const String _projectId = '52dc35105b74ddd9ade472de308b02d5';

  static const PairingMetadata _metadata = PairingMetadata(
    name: 'TPIX Wallet',
    description: 'Official wallet for TPIX Chain — gasless, fast, secure.',
    url: 'https://tpix.online',
    // โลโก้เหรียญ TPIX ตัวใหม่ (แทน /tpixlogo.webp ตัวเก่า) — ?v=2 กันแคช Cloudflare รูปเก่า
    icons: ['https://tpix.online/images/brand/tpix-coin.png?v=2'],
    redirect: Redirect(
      native: 'tpixwallet://',
      universal: 'https://tpix.online/wallet',
    ),
  );

  /// Supported EVM chains: TPIX (4289), BSC (56), Polygon (137), ETH (1)
  static final List<String> _supportedChains =
      ChainConfig.all.map((c) => 'eip155:${c.chainId}').toList();

  static final Set<int> _supportedChainIds = ChainConfig.all.map((c) => c.chainId).toSet();

  static const List<String> _supportedMethods = [
    'personal_sign',
    'eth_sign',
    'eth_signTransaction',
    'eth_sendTransaction',
    'eth_signTypedData',
    'eth_signTypedData_v4',
    'wallet_switchEthereumChain',
    'wallet_addEthereumChain',
  ];

  static const List<String> _supportedEvents = [
    'chainChanged',
    'accountsChanged',
  ];

  /// pair มาก่อน init เสร็จ (เปิดแอปเย็นจากลิงก์ของเว็บ) → รอได้นานสุดเท่านี้ แล้วค่อยบอกว่าเชื่อมไม่สำเร็จ
  static const readyTimeout = Duration(seconds: 15);

  /// ช่วงที่โชว์ "กำลังรอคำขอจากเว็บ…" หลังถูกเปิดจากลิงก์ (คำขอวิ่งทาง relay มาถึงทีหลังลิงก์ได้)
  static const browserWaitWindow = Duration(seconds: 30);

  /// คำขอที่รอผู้ใช้ได้มากสุด — เว็บที่ยิงคำขอรัว ๆ ไม่ทำให้คิวโตไม่จำกัด
  static const _maxQueuedRequests = 20;

  // ================================================================
  //  State
  // ================================================================

  final Future<bool> Function() _moveToBack;
  final DateTime Function() _clock;

  ReownWalletKit? _walletKit;
  WalletProvider? _walletProvider;

  bool _initialized = false;
  bool get initialized => _initialized;
  bool _initializing = false;
  bool _disposed = false;

  /// pair ที่รอ init รอบปัจจุบันจบ (สำเร็จหรือล้ม)
  final List<Completer<void>> _initWaiters = [];

  /// คำขอที่ SDK ส่งมาระหว่าง init — ยังตอบเองไม่ได้ เก็บไว้ทำต่อตอน init เสร็จ
  final List<SessionRequestEvent> _earlyRequests = [];

  /// คิวคำขอเชื่อมต่อ / คำขอเซ็น — ตัวหน้าสุดโชว์บนการ์ด ตอบแล้วตัวถัดไปขึ้นแทน
  /// (เดิมช่องเดียว: คำขอที่สองทับตัวแรก เว็บรอคำตอบตัวแรกไปตลอดกาล)
  final List<SessionProposalEvent> _proposals = [];
  final List<SessionRequestEvent> _requests = [];

  /// id คำขอที่รับเข้ามาแล้ว — SDK กับการกวาดคลังคำขอค้างส่งตัวเดียวกันซ้ำได้
  final LinkedHashSet<int> _seenRequestIds = LinkedHashSet<int>();

  /// กำลังส่งคำตอบอยู่ — กันแตะซ้ำแล้วตอบสองรอบ (หรือไปตอบตัวถัดไปที่ผู้ใช้ยังไม่เห็น)
  bool _busy = false;
  bool get busy => _busy;

  WcNotice? _notice;

  /// ข้อความที่หน้าเชื่อมต่อต้องโชว์ผู้ใช้ (null = ไม่มี)
  WcNotice? get notice => _notice;

  WcVisit? _visit;
  Timer? _visitTimer;

  /// คำขอที่เพิ่งตอบไป (id → เวลา + มีข้อความให้ผู้ใช้อ่านไหม)
  /// relay ส่งคำขอมาถึงก่อนลิงก์ requestId ของเว็บได้ (เช่น สลับเชนที่ตอบเองทันที) — ลิงก์มาทีหลังต้องไม่รอเก้อ
  final LinkedHashMap<int, ({DateTime at, bool notice})> _recentAnswers = LinkedHashMap();

  /// Current pending session proposal (head of the queue)
  SessionProposalEvent? get pendingProposal => _proposals.isEmpty ? null : _proposals.first;

  /// Current pending session request (head of the queue)
  SessionRequestEvent? get pendingRequest => _requests.isEmpty ? null : _requests.first;

  /// Active sessions
  List<SessionData> get sessions =>
      _initialized ? (_walletKit?.sessions.getAll() ?? const []) : const [];

  /// Whether there's a pending approval to show
  bool get hasPendingProposal => _proposals.isNotEmpty;
  bool get hasPendingRequest => _requests.isNotEmpty;

  /// จำนวนคำขอในคิว (รวมตัวที่โชว์อยู่)
  int get pendingRequestCount => _requests.length;

  /// Callback when a session proposal arrives (UI should show approval dialog)
  void Function(SessionProposalEvent)? onProposalReceived;

  /// Callback when a sign/tx request needs the user (หรือมีข้อความเรื่องคำขอที่ผู้ใช้ต้องเห็น)
  void Function(SessionRequestEvent)? onRequestReceived;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// โชว์ข้อความบนหน้าเชื่อมต่อ (เช่น ลิงก์จากเว็บเสีย)
  void showNotice(WcNotice notice) {
    _notice = notice;
    _notify();
  }

  /// [notify] false = ตอนหน้าเชื่อมต่อกำลังถูกรื้อ (แจ้ง listener ตอนนั้นไม่ได้)
  void clearNotice({bool notify = true}) {
    if (_notice == null) return;
    _notice = null;
    if (notify) _notify();
  }

  // ================================================================
  //  Init
  // ================================================================

  /// Initialize WalletConnect SDK. Call once after wallet is unlocked.
  Future<void> init(WalletProvider walletProvider) async {
    _walletProvider = walletProvider;
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      final kit = ReownWalletKit(
        core: ReownCore(projectId: _projectId),
        metadata: _metadata,
      );

      // สมัครรับ event "ก่อน" init — ตอน init SDK resubscribe แล้ว relay ส่งคำขอที่ค้างไว้เข้ามาได้ทันที
      // (เปิดแอปเย็นจากลิงก์ requestId ของเว็บ) สมัครทีหลังจะพลาดคำขอนั้นไปเงียบ ๆ
      _registerEventHandlers(kit);
      await kit.init();

      _walletKit = kit;
      _initialized = true;
      debugPrint('[WC] WalletConnect initialized');

      final early = List.of(_earlyRequests);
      _earlyRequests.clear();
      for (final event in early) {
        _intakeRequest(kit, event);
      }
      final visit = _visit;
      if (visit != null) _recoverPendingFor(visit);
      _notify();
    } catch (e) {
      debugPrint('[WC] Init failed: ${e.runtimeType}');
    } finally {
      _initializing = false;
      for (final waiter in _initWaiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
      _initWaiters.clear();
    }
  }

  void _registerEventHandlers(ReownWalletKit kit) {
    // Session proposal — dApp wants to connect
    kit.onSessionProposal.subscribe(_handleSessionProposal);
    kit.onProposalExpire.subscribe(_handleProposalExpire);

    // Session request — dApp wants wallet to do something
    kit.onSessionRequest.subscribe(_handleSessionRequest);

    // Session delete / expire — dApp disconnected → คำขอค้างของ session นั้นไม่มีใครรอแล้ว
    kit.onSessionDelete.subscribe((e) => _dropSession(e.topic));
    kit.onSessionExpire.subscribe((e) => _dropSession(e.topic));

    // Register request handlers for ทุกเชน × ทุกเมธอด — เดิมลงทะเบียนแค่
    // eip155:4289 ทำให้คำขอบนเชนอื่น (เช่น personal_sign/eth_sendTransaction
    // ตอนเทรดจริงบน BSC จากเว็บผ่าน QR) ถูก SDK ปฏิเสธอัตโนมัติ
    // โดยไม่เข้า flow ยืนยันของผู้ใช้เลย
    for (final chain in _supportedChains) {
      for (final method in _supportedMethods) {
        kit.registerRequestHandler(
          chainId: chain,
          method: method,
        );
      }
    }
  }

  /// รอให้ init เสร็จ — true = พร้อมใช้
  Future<bool> _waitUntilReady(Duration timeout) async {
    if (_initialized) return true;
    final wallet = _walletProvider;
    // init รอบก่อนล้มไปแล้ว (เช่น เปิดแอปตอนเน็ตหลุด) → ลองใหม่เลย
    if (!_initializing && wallet != null) unawaited(init(wallet));
    if (_initialized) return true;

    final waiter = Completer<void>();
    _initWaiters.add(waiter);
    final timer = Timer(timeout, () {
      if (!waiter.isCompleted) waiter.complete();
    });
    await waiter.future;
    timer.cancel();
    _initWaiters.remove(waiter);
    return _initialized && !_disposed;
  }

  // ================================================================
  //  Pairing (QR scan / deep link)
  // ================================================================

  /// Parse a WalletConnect URI and initiate pairing.
  /// Called when user scans QR code or opens wc: / tpixwallet://wc?uri= deep link.
  ///
  /// เปิดแอปเย็นจากลิงก์ = มาถึงก่อน init เสร็จ → รอ init สูงสุด [readyTimeout] ก่อนยอมแพ้
  /// โยน [WalletConnectPairException] เสมอเมื่อไม่สำเร็จ (ข้อความไม่มี URI — มี symKey)
  Future<void> pair(String uri) async {
    final topic = WcDeepLink.pairingTopicOf(uri);
    try {
      if (topic == null) throw const WalletConnectPairException('invalid_uri');
      if (!await _waitUntilReady(readyTimeout)) throw const WalletConnectPairException('not_ready');
      await _walletKit!.pair(uri: Uri.parse(uri.trim()));
      debugPrint('[WC] Pairing initiated');
    } catch (e) {
      // ห้าม log ตัว error ดิบ — FormatException ของ Uri มีทั้ง URI (symKey) ติดมา
      debugPrint('[WC] Pairing failed: ${e.runtimeType}');
      // ลิงก์จับคู่จากเบราว์เซอร์ล้ม = ไม่มีคำขอเชื่อมต่อตามมาแน่ → เลิกนับว่ามาจากเบราว์เซอร์
      final visit = _visit;
      if (visit != null && visit.kind == WcVisitKind.pair && (visit.topic == null || visit.topic == topic)) {
        _endVisit();
        _notify();
      }
      if (e is WalletConnectPairException) rethrow;
      throw const WalletConnectPairException('pair_failed');
    }
  }

  // ================================================================
  //  Browser visit (เปิดจาก tpixwallet://wc ของเว็บบนมือถือ)
  // ================================================================

  /// แอปถูกเปิดจากลิงก์ tpixwallet://wc — ตอบตัวที่ลิงก์รอเสร็จแล้วพากลับเบราว์เซอร์ (ดู [WcVisit])
  /// ลิงก์เสีย = ไม่นับ (และล้างรอบเดิม — ลิงก์ล่าสุดชนะเสมอ)
  void beginBrowserVisit(WcDeepLink link) {
    final now = _clock();
    final visit = WcVisit.fromLink(link, now);
    _endVisit();

    // คำขอที่ลิงก์นี้พูดถึงถูกตอบไปแล้ว (relay มาถึงก่อนลิงก์) → เว็บได้คำตอบแล้ว ไม่ต้องรอ
    // มีข้อความให้อ่าน (เช่น เว็บขอกระเป๋าอื่น) = อยู่ในแอป · ไม่มี = พากลับเบราว์เซอร์ทันที
    final rid = visit?.requestId;
    final answered = rid == null ? null : _recentAnswers[rid];
    if (answered != null && !now.isBefore(answered.at) && now.difference(answered.at) < WcVisit.ttl) {
      _notify();
      if (!answered.notice) unawaited(_moveBackSafely());
      return;
    }

    _visit = visit;
    if (visit != null && visit.kind != WcVisitKind.open) {
      // ปิดป้าย "กำลังรอ…" เองเมื่อหมดช่วงรอ (ไม่งั้นค้างจนกว่าจะมีอะไรให้วาดใหม่)
      _visitTimer = Timer(browserWaitWindow, _notify);
    }
    if (visit != null) _recoverPendingFor(visit);
    _notify();
  }

  /// flow ในแอป (กดสแกน QR เอง) — ห้ามพากลับเบราว์เซอร์
  void endBrowserVisit() {
    if (_visit == null) return;
    _endVisit();
    _notify();
  }

  void _endVisit() {
    _visit = null;
    _visitTimer?.cancel();
    _visitTimer = null;
  }

  /// ถูกเปิดจากลิงก์คำขอของเว็บ แต่คำขอยังวิ่งมาไม่ถึง — หน้าเชื่อมต่อโชว์ "กำลังรอคำขอจากเว็บ…"
  bool get awaitingBrowserRequest => _awaiting(WcVisitKind.request);

  /// ถูกเปิดจากลิงก์จับคู่ของเว็บ แต่คำขอเชื่อมต่อยังมาไม่ถึง — โชว์ "กำลังเชื่อมต่อ…" ต่อ
  bool get awaitingBrowserProposal => _awaiting(WcVisitKind.pair);

  bool _awaiting(WcVisitKind kind) {
    final visit = _visit;
    if (visit == null || visit.kind != kind || _proposals.isNotEmpty || _requests.isNotEmpty) return false;
    final age = _clock().difference(visit.startedAt);
    return !age.isNegative && age < browserWaitWindow;
  }

  /// คำขอที่ SDK รับไว้แล้วแต่แอปไม่มีในคิว (เช่น ระบบปิดแอปทิ้งหลังรับคำขอ แล้วเว็บเด้งกลับมาเปิดใหม่)
  /// กวาดเฉพาะตัวที่ลิงก์ระบุ — ไม่ขุดคำขอเก่าค้างข้ามวันขึ้นมาให้ผู้ใช้เซ็น
  void _recoverPendingFor(WcVisit visit) {
    final kit = _walletKit;
    if (kit == null || !_initialized) return; // init เสร็จแล้วเรียกซ้ำเอง
    if (visit.requestId == null && (visit.kind != WcVisitKind.request || visit.topic == null)) return;
    final Map<String, SessionRequest> pending;
    try {
      pending = kit.getPendingSessionRequests();
    } catch (e) {
      debugPrint('[WC] pending requests unavailable: ${e.runtimeType}');
      return;
    }
    final now = _clock();
    for (final request in pending.values) {
      final wanted = visit.requestId != null
          ? request.id == visit.requestId
          : request.topic.toLowerCase() == visit.topic && _isRecentRequestId(request.id, now);
      if (!wanted || _seenRequestIds.contains(request.id)) continue;
      _intakeRequest(kit, SessionRequestEvent.fromSessionRequest(request));
    }
  }

  /// id ของ JSON-RPC ฝั่ง WalletConnect JS = เวลา(ms) × 1000 + สุ่ม — ใช้ดูอายุคำขอได้
  static bool _isRecentRequestId(int id, DateTime now) {
    final age = now.millisecondsSinceEpoch - id ~/ 1000;
    return age >= -const Duration(minutes: 1).inMilliseconds && age <= const Duration(minutes: 10).inMilliseconds;
  }

  Future<void> _afterAnswer(WcAnswered answered, {required bool delivered, required bool notice}) async {
    final now = _clock();
    if (answered.kind == WcAnswerKind.request) {
      _recentAnswers.remove(answered.id);
      _recentAnswers[answered.id] = (at: now, notice: notice || !delivered);
      while (_recentAnswers.length > 64) {
        _recentAnswers.remove(_recentAnswers.keys.first);
      }
    }

    final visit = _visit;
    if (visit == null) return;
    final step = visit.afterAnswer(
      answered,
      delivered: delivered,
      notice: notice,
      morePending: _proposals.isNotEmpty || _requests.isNotEmpty,
      now: now,
    );
    if (step.visit == null) {
      _endVisit();
    } else {
      _visit = step.visit;
    }
    if (step.moveBack) await _moveBackSafely();
  }

  Future<void> _moveBackSafely() async {
    try {
      await _moveToBack();
    } catch (e) {
      debugPrint('[WC] move to back failed: ${e.runtimeType}');
    }
  }

  /// เทสต์: เล่นขั้น "หลังตอบ" เหมือนตอนส่งคำตอบให้เว็บเสร็จ (ไม่ต้องมี SDK / relay จริง)
  @visibleForTesting
  Future<void> debugAfterAnswer(WcAnswered answered, {bool delivered = true, bool notice = false}) =>
      _afterAnswer(answered, delivered: delivered, notice: notice);

  // ================================================================
  //  Session Proposal
  // ================================================================

  void _handleSessionProposal(SessionProposalEvent? event) {
    if (event == null || _proposals.any((p) => p.id == event.id)) return;
    _proposals.add(event);
    _notify();
    onProposalReceived?.call(event);
  }

  void _handleProposalExpire(SessionProposalEvent? event) {
    if (event == null) return;
    final before = _proposals.length;
    _proposals.removeWhere((p) => p.id == event.id);
    if (_proposals.length != before) _notify();
  }

  /// Approve the session proposal the user is looking at ([proposalId] = ตัวที่โชว์บนการ์ด).
  Future<void> approveProposal(int proposalId) async {
    final proposal = pendingProposal;
    final kit = _walletKit;
    final address = _walletProvider?.address;
    if (proposal == null || proposal.id != proposalId || kit == null || address == null || _busy) return;

    _busy = true;
    _notice = null;
    _notify();
    var delivered = false;
    try {
      // Build approved namespaces — approve all supported chains with wallet address
      final accounts = ChainConfig.all
          .map((c) => 'eip155:${c.chainId}:$address')
          .toList();

      final approvedNamespaces = {
        'eip155': Namespace(
          chains: _supportedChains,
          accounts: accounts,
          methods: _supportedMethods,
          events: _supportedEvents,
        ),
      };

      await kit.approveSession(
        id: proposal.id,
        namespaces: approvedNamespaces,
      );
      delivered = true;
      debugPrint('[WC] Session approved');
    } catch (e) {
      debugPrint('[WC] Approve failed: ${e.runtimeType}');
      _notice = const WcNotice('wc.approveFailed');
    } finally {
      _proposals.removeWhere((p) => p.id == proposal.id);
      _busy = false;
      _notify();
    }
    await _afterAnswer(_answeredProposal(proposal), delivered: delivered, notice: !delivered);
  }

  /// Reject the session proposal the user is looking at.
  Future<void> rejectProposal(int proposalId) async {
    final proposal = pendingProposal;
    final kit = _walletKit;
    if (proposal == null || proposal.id != proposalId || kit == null || _busy) return;

    _busy = true;
    _notice = null;
    _notify();
    var delivered = false;
    try {
      await kit.rejectSession(
        id: proposal.id,
        reason: Errors.getSdkError(Errors.USER_REJECTED).toSignError(),
      );
      delivered = true;
    } catch (e) {
      debugPrint('[WC] Reject failed: ${e.runtimeType}');
      _notice = const WcNotice('wc.answerFailed');
    } finally {
      _proposals.removeWhere((p) => p.id == proposal.id);
      _busy = false;
      _notify();
    }
    await _afterAnswer(_answeredProposal(proposal), delivered: delivered, notice: !delivered);
  }

  WcAnswered _answeredProposal(SessionProposalEvent proposal) => WcAnswered(
        kind: WcAnswerKind.proposal,
        id: proposal.id,
        topics: {proposal.params.pairingTopic.toLowerCase()},
      );

  // ================================================================
  //  Session Requests (sign / send)
  // ================================================================

  void _handleSessionRequest(SessionRequestEvent? event) {
    if (event == null) return;
    final kit = _walletKit;
    if (kit == null || !_initialized) {
      _earlyRequests.add(event);
      return;
    }
    _intakeRequest(kit, event);
  }

  /// คำขอเข้ามา → ตอบเอง (เปลี่ยนเชน / ปฏิเสธ) หรือเข้าคิวให้ผู้ใช้ยืนยัน
  void _intakeRequest(ReownWalletKit kit, SessionRequestEvent event) {
    if (!_markSeen(event.id)) return;
    final intake = WcRequestRules.decideIntake(
      method: event.method,
      params: event.params,
      supportedChainIds: _supportedChainIds,
      activeAddress: _walletProvider?.address,
    );
    switch (intake) {
      case WcAutoOk(:final chainChanged):
        unawaited(_answerAutoOk(kit, event, chainChanged));
      case final WcAutoReject reject:
        unawaited(_answerAutoReject(kit, event, reject));
      case WcAskUser():
        if (_requests.length >= _maxQueuedRequests) {
          unawaited(_answerAutoReject(
            kit,
            event,
            const WcAutoReject(code: -32005, message: 'Too many pending requests'),
          ));
          return;
        }
        _requests.add(event);
        _notify();
        onRequestReceived?.call(event);
    }
  }

  bool _markSeen(int id) {
    if (!_seenRequestIds.add(id)) return false;
    while (_seenRequestIds.length > 256) {
      _seenRequestIds.remove(_seenRequestIds.first);
    }
    return true;
  }

  /// สลับ/เพิ่มเชนที่รองรับ → สำเร็จ (result null) + แจ้ง chainChanged ตอนสลับ
  Future<void> _answerAutoOk(ReownWalletKit kit, SessionRequestEvent event, int? chainChanged) async {
    var delivered = false;
    try {
      // EIP-3326/3085: สำเร็จ = result null แต่ respondSessionRequest ของ SDK ไม่ยอมให้ result
      // และ error เป็น null พร้อมกัน → ส่งผลลัพธ์ผ่าน pairing ตรง ๆ (ทางเดียวกับที่ SDK ใช้ข้างใน)
      // แล้วลบออกจากคลังคำขอค้างเอง (ไม่งั้นค้างอยู่ใน getPendingSessionRequests)
      await kit.core.pairing.sendResult(event.id, event.topic, MethodConstants.WC_SESSION_REQUEST, null);
      await kit.pendingRequests.delete(event.id.toString());
      delivered = true;
    } catch (e) {
      debugPrint('[WC] auto answer failed: ${e.runtimeType}');
    }
    if (delivered && chainChanged != null) {
      try {
        await kit.emitSessionEvent(
          topic: event.topic,
          chainId: 'eip155:$chainChanged',
          event: SessionEventParams(name: 'chainChanged', data: chainChanged),
        );
      } catch (e) {
        // session รุ่นเก่าที่ไม่ได้อนุมัติ event นี้ — คำตอบหลักไปแล้ว ไม่ต้องทำอะไรต่อ
        debugPrint('[WC] chainChanged emit failed: ${e.runtimeType}');
      }
    }
    await _afterAnswer(_answeredRequest(event, auto: true), delivered: delivered, notice: false);
  }

  /// ปฏิเสธเอง — เว็บขอกระเป๋าอื่น (4100 wallet_changed) ต้องบอกผู้ใช้ด้วยว่าเว็บรอที่อยู่ไหน
  Future<void> _answerAutoReject(ReownWalletKit kit, SessionRequestEvent event, WcAutoReject reject) async {
    final delivered = await _respondError(kit, event, JsonRpcError(code: reject.code, message: reject.message));
    final expected = reject.walletExpected;
    if (expected != null) {
      _notice = _walletChangedNotice(expected);
      _notify();
      onRequestReceived?.call(event); // ให้หน้าแรกเปิดหน้าเชื่อมต่อขึ้นมาโชว์ข้อความ
    }
    await _afterAnswer(_answeredRequest(event, auto: true), delivered: delivered, notice: expected != null);
  }

  WcNotice _walletChangedNotice(String expected) {
    final active = _walletProvider?.address;
    return WcNotice('wc.walletChanged', {
      'expected': wcShortAddress(expected),
      'active': active == null ? '—' : wcShortAddress(active),
    });
  }

  Future<bool> _respondError(ReownWalletKit kit, SessionRequestEvent event, JsonRpcError error) async {
    try {
      await kit.respondSessionRequest(
        topic: event.topic,
        response: JsonRpcResponse(id: event.id, error: error),
      );
      return true;
    } catch (e) {
      debugPrint('[WC] respond error failed: ${e.runtimeType}');
      return false;
    }
  }

  WcAnswered _answeredRequest(SessionRequestEvent event, {bool auto = false}) {
    String? pairingTopic;
    try {
      pairingTopic = _walletKit?.sessions.get(event.topic)?.pairingTopic;
    } catch (_) {
      pairingTopic = null;
    }
    return WcAnswered(
      kind: WcAnswerKind.request,
      id: event.id,
      topics: {event.topic.toLowerCase(), if (pairingTopic != null) pairingTopic.toLowerCase()},
      auto: auto,
    );
  }

  /// Approve and execute the request the user is looking at ([requestId] = ตัวที่โชว์บนการ์ด).
  Future<void> approveRequest(int requestId) async {
    final request = pendingRequest;
    final kit = _walletKit;
    final wallet = _walletProvider;
    if (request == null || request.id != requestId || kit == null || wallet == null || _busy) return;

    _busy = true;
    _notice = null;
    _notify();

    JsonRpcResponse response;
    WcNotice? notice;
    // เช็กอีกรอบตอนกด — ผู้ใช้อาจสลับกระเป๋าหลังคำขอเข้ามา
    final requested = WcRequestRules.requestedAddress(request.method, request.params).address;
    final expected = WcRequestRules.walletChangedExpected(requested: requested, active: wallet.address);
    if (expected != null) {
      response = JsonRpcResponse(
        id: request.id,
        error: const JsonRpcError(code: WcRequestRules.walletChangedCode, message: WcRequestRules.walletChangedMessage),
      );
      notice = _walletChangedNotice(expected);
    } else {
      try {
        final result = await _execute(request, wallet);
        response = JsonRpcResponse(id: request.id, result: result);
        debugPrint('[WC] Request approved: ${request.method}');
      } catch (e) {
        debugPrint('[WC] Request failed: ${e.runtimeType}');
        response = JsonRpcResponse(id: request.id, error: _errorFor(e));
        notice = e is WalletChangedException && requested != null ? _walletChangedNotice(requested) : _noticeFor(e);
      }
    }

    var delivered = false;
    try {
      await kit.respondSessionRequest(topic: request.topic, response: response);
      delivered = true;
    } catch (e) {
      debugPrint('[WC] respond failed: ${e.runtimeType}');
      // ธุรกรรมอาจออกไปแล้วแต่เว็บไม่รู้ — บอกให้ดูประวัติก่อนลองซ้ำ
      notice ??= WcNotice(request.method == 'eth_sendTransaction' ? 'wc.answerFailedTx' : 'wc.answerFailed');
    } finally {
      _requests.removeWhere((r) => r.id == request.id);
      _notice = notice;
      _busy = false;
      _notify();
    }
    await _afterAnswer(_answeredRequest(request), delivered: delivered, notice: notice != null);
  }

  /// Reject the request the user is looking at.
  Future<void> rejectRequest(int requestId) async {
    final request = pendingRequest;
    final kit = _walletKit;
    if (request == null || request.id != requestId || kit == null || _busy) return;

    _busy = true;
    _notice = null;
    _notify();
    final delivered = await _respondError(
      kit,
      request,
      const JsonRpcError(code: 4001, message: 'User rejected the request'),
    );
    _requests.removeWhere((r) => r.id == request.id);
    if (!delivered) _notice = const WcNotice('wc.answerFailed');
    _busy = false;
    _notify();
    await _afterAnswer(_answeredRequest(request), delivered: delivered, notice: !delivered);
  }

  /// คำขอที่ผู้ใช้ยืนยัน → ลายเซ็น / tx hash
  Future<String> _execute(SessionRequestEvent request, WalletProvider wallet) async {
    switch (request.method) {
      case 'personal_sign':
      case 'eth_sign':
        final parsed = WcSignParams.parse(request.method, request.params);
        if (parsed == null) throw const _WcRequestError(-32602, 'Invalid params');
        // ไบต์ดิบตามที่เว็บส่ง — ระบุที่อยู่มา = ให้ WalletService เช็กซ้ำตอนเซ็นจริง
        return wallet.signPersonalMessageBytes(parsed.message, expectedAddress: parsed.address);
      case 'eth_sendTransaction':
        return _handleSendTransaction(request.params, request.chainId, wallet);
      case 'eth_signTypedData':
      case 'eth_signTypedData_v4':
        return _handleSignTypedData(request.params, wallet);
      default:
        throw const _WcRequestError(4200, 'Unsupported method');
    }
  }

  /// error ที่ส่งกลับให้เว็บ — ไม่ส่ง toString() ดิบ (อาจมี URL ของ RPC / path ภายใน)
  static JsonRpcError _errorFor(Object e) {
    if (e is _WcRequestError) return JsonRpcError(code: e.code, message: e.message);
    if (e is WalletChangedException) {
      return const JsonRpcError(code: WcRequestRules.walletChangedCode, message: WcRequestRules.walletChangedMessage);
    }
    if (e is InsufficientGasException) {
      return const JsonRpcError(code: -32000, message: 'Insufficient balance for network fee');
    }
    if (e is RpcException) return JsonRpcError(code: -32000, message: _nodeMessage(e));
    return const JsonRpcError(code: -32603, message: 'Internal error');
  }

  /// ข้อความที่ผู้ใช้เห็นในแอป — ห้ามมี Exception ดิบ
  static WcNotice _noticeFor(Object e) {
    if (e is InsufficientGasException) return const WcNotice('send.errGas');
    if (e is RpcUnavailableException) return const WcNotice('wc.errNetwork');
    if (e is RpcException) {
      final m = e.message.toLowerCase();
      if (m.contains('insufficient funds') || m.contains('exceeds balance')) {
        return const WcNotice('send.insufficientBalance');
      }
      // ข้อความจากโหนด (เช่น execution reverted) — ไม่มี URL/ข้อมูลลับ แสดงต่อท้ายได้
      return WcNotice('wc.requestFailed', const {}, _nodeMessage(e));
    }
    return const WcNotice('wc.requestFailed');
  }

  static String _nodeMessage(RpcException e) {
    final clean = e.message.replaceAll(RegExp(r'https?://\S+'), '[server]');
    return clean.length > 120 ? '${clean.substring(0, 120)}…' : clean;
  }

  // ================================================================
  //  Method Handlers
  // ================================================================

  /// eth_sendTransaction: params = [{ from, to, value, data, gas, gasPrice }]
  Future<String> _handleSendTransaction(dynamic params, String chainId, WalletProvider wallet) async {
    final List<dynamic> paramList = params is List ? params : [params];
    if (paramList.isEmpty || paramList[0] is! Map) throw const _WcRequestError(-32602, 'Invalid params');

    final tx = Map<String, dynamic>.from(paramList[0] as Map);
    final to = tx['to'];
    if (to is! String) throw const _WcRequestError(-32602, 'Invalid params');
    final valueHex = tx['value'] as String? ?? '0x0';
    final dataHex = tx['data'] as String?;
    final gasHex = tx['gas'] as String?;
    final gasPriceHex = tx['gasPrice'] as String?;
    final from = tx['from'] as String?;

    // Parse chain ID from WC namespace (eip155:4289 → 4289) — เชนที่แอปไม่รู้จัก ห้ามตกไปใช้ TPIX แทน
    final chainIdNum = int.tryParse(chainId.split(':').last);
    if (chainIdNum == null || !_supportedChainIds.contains(chainIdNum)) {
      throw const _WcRequestError(4901, 'Chain not supported');
    }
    final chain = ChainConfig.byId(chainIdNum);

    final value = _hexQuantity(valueHex);

    Uint8List? data;
    if (dataHex != null && dataHex != '0x' && dataHex.length > 2) {
      data = _hexToBytes(dataHex.startsWith('0x') ? dataHex.substring(2) : dataHex);
    }

    int? maxGas;
    if (gasHex != null) {
      maxGas = _hexQuantity(gasHex).toInt();
    }

    BigInt? gasPrice;
    if (chain.isGasless) {
      gasPrice = BigInt.zero;
    } else if (gasPriceHex != null) {
      gasPrice = _hexQuantity(gasPriceHex);
    }

    return wallet.sendEvmTransaction(
      rpcUrl: chain.rpcUrl,
      chainId: chainIdNum,
      toAddress: to,
      value: value,
      data: data,
      maxGas: maxGas,
      gasPrice: gasPrice,
      // เว็บระบุ from มา = ต้องเป็นใบนี้ตอนเซ็นจริง (สลับกระเป๋าระหว่างส่ง → WalletChangedException)
      expectedFrom: from,
    );
  }

  /// eth_signTypedData: params = [address, typed_data_json]
  Future<String> _handleSignTypedData(dynamic params, WalletProvider wallet) async {
    // For typed data, we sign the raw JSON as personal message (simplified)
    // Full EIP-712 implementation would require encoding the struct
    final List<dynamic> paramList = params is List ? params : [params];
    if (paramList.length < 2) throw const _WcRequestError(-32602, 'Invalid params');

    final typedDataStr = paramList[1].toString();
    return wallet.signPersonalMessage(typedDataStr);
  }

  // ================================================================
  //  Session Management
  // ================================================================

  void _dropSession(String? topic) {
    if (topic != null) _requests.removeWhere((r) => r.topic == topic);
    _notify();
  }

  /// Disconnect a specific session.
  Future<void> disconnectSession(String topic) async {
    final kit = _walletKit;
    if (kit == null) return;

    try {
      await kit.disconnectSession(
        topic: topic,
        reason: Errors.getSdkError(Errors.USER_DISCONNECTED).toSignError(),
      );
      _requests.removeWhere((r) => r.topic == topic);
      _notify();
      debugPrint('[WC] Session disconnected: $topic');
    } catch (e) {
      debugPrint('[WC] Disconnect failed: ${e.runtimeType}');
    }
  }

  /// Disconnect all sessions.
  Future<void> disconnectAll() async {
    for (final session in sessions) {
      await disconnectSession(session.topic);
    }
  }

  /// Get human-readable info about a session's peer dApp.
  Map<String, String> getPeerInfo(SessionData session) {
    final peer = session.peer.metadata;
    return {
      'name': peer.name,
      'url': peer.url,
      'icon': peer.icons.isNotEmpty ? peer.icons.first : '',
      'description': peer.description,
    };
  }

  // ================================================================
  //  Helpers
  // ================================================================

  /// สิ่งที่โชว์บนการ์ดคำขอตัวหน้าสุดของคิว
  WcRequestView? get pendingRequestView {
    final request = pendingRequest;
    if (request == null) return null;
    return WcRequestView.build(method: request.method, params: request.params, chainId: request.chainId);
  }

  /// เว็บเจ้าของคำขอ (ชื่อ / ที่อยู่) — null = ไม่รู้จัก session นั้น
  PairingMetadata? peerOf(String topic) {
    try {
      return _walletKit?.sessions.get(topic)?.peer.metadata;
    } catch (_) {
      return null;
    }
  }

  /// เทสต์: ใส่คำขอเชื่อมต่อเข้าคิวเหมือน SDK ส่งมา (ไม่ต้องมี relay จริง)
  @visibleForTesting
  void debugAddProposal(SessionProposalEvent event) => _handleSessionProposal(event);

  static BigInt _hexQuantity(String raw) {
    final s = raw.trim().toLowerCase();
    final digits = s.startsWith('0x') ? s.substring(2) : s;
    if (digits.isEmpty) return BigInt.zero;
    final value = BigInt.tryParse(digits, radix: 16);
    if (value == null) throw const _WcRequestError(-32602, 'Invalid params');
    return value;
  }

  Uint8List _hexToBytes(String hex) {
    if (hex.length.isOdd) throw const _WcRequestError(-32602, 'Invalid params');
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) throw const _WcRequestError(-32602, 'Invalid params');
      result[i] = byte;
    }
    return result;
  }

  // ================================================================
  //  Cleanup
  // ================================================================

  @override
  void dispose() {
    _disposed = true;
    _visitTimer?.cancel();
    for (final waiter in _initWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _initWaiters.clear();
    final kit = _walletKit;
    kit?.onSessionProposal.unsubscribeAll();
    kit?.onProposalExpire.unsubscribeAll();
    kit?.onSessionRequest.unsubscribeAll();
    kit?.onSessionDelete.unsubscribeAll();
    kit?.onSessionExpire.unsubscribeAll();
    super.dispose();
  }
}

/// ข้อความถึงผู้ใช้บนหน้าเชื่อมต่อ — [key] ของ LocaleProvider + ค่าแทนที่ {ชื่อ}
/// [detail] = ข้อความสั้นจากโหนด (ต่อท้าย ไม่ต้องแปล) — ห้ามใส่ toString() ของ Exception
@immutable
class WcNotice {
  final String key;
  final Map<String, String> params;
  final String? detail;

  const WcNotice(this.key, [this.params = const {}, this.detail]);
}

/// จับคู่ไม่สำเร็จ — [reason] ไว้ debug เท่านั้น ห้ามมี URI (มี symKey)
class WalletConnectPairException implements Exception {
  final String reason;
  const WalletConnectPairException(this.reason);

  @override
  String toString() => 'WalletConnectPairException($reason)';
}

/// คำขอผิดรูป / เมธอดไม่รองรับ — ส่งรหัสนี้กลับให้เว็บตรง ๆ
class _WcRequestError implements Exception {
  final int code;
  final String message;
  const _WcRequestError(this.code, this.message);
}
