/// TPIX Wallet — หน้าเชื่อมต่อ dApp (WalletConnect)
///
/// สิ่งที่ห้ามพัง:
///   - จับคู่ไม่สำเร็จ (QR หมดอายุ / ตัวเชื่อมยังไม่พร้อม) → ข้อความที่อ่านรู้เรื่อง ไม่ใช่ Exception ดิบ
///     (ทุกธีม — เดิมโชว์ e.toString())
///   - เปิดแอปเย็นจากลิงก์: pair มาก่อน init เสร็จ → รอ init ก่อน (ไม่ล้มทันทีด้วย "not initialized")
///   - ธีม Obsidian: ยังไม่มีการเชื่อมต่อ → ข้อความว่าง + ปุ่มสแกนพร้อมใช้
///   - กันเว็บปลอม: Verify บอก INVALID / SCAM / โดเมนไม่ตรง → เตือนแดงบนการ์ด (ทั้งสองธีม)
///     SCAM → ปุ่มหลักเป็น "ปฏิเสธ" แต่ยังกดอนุมัติได้ (ผู้ใช้ตัดสินใจเอง)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:reown_walletkit/reown_walletkit.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/core/themes/theme_bundle.dart';
import 'package:tpix_wallet/screens/dapp_connect_screen.dart';
import 'package:tpix_wallet/services/walletconnect_service.dart';
import 'package:tpix_wallet/services/wc_deep_link.dart';
import 'package:tpix_wallet/widgets/obsidian/obsidian.dart';

import 'support/test_theme.dart';

/// wc: URI รูปแบบถูกต้อง (มี symKey) — ใช้ทดสอบทาง "ตัวเชื่อมยังไม่พร้อม" ไม่ใช่ "URI เสีย"
final _validUri = 'wc:${'a1' * 32}@2?relay-protocol=irn&symKey=${'b2' * 32}';

Widget _harness(ThemeId theme, {String? uri, WalletConnectService? wc}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        // ยังไม่ได้ init (ไม่มีกระเป๋า) → pair() รอ init จนหมดเวลา แล้วโยน WalletConnectPairException
        if (wc == null)
          ChangeNotifierProvider(create: (_) => WalletConnectService())
        else
          ChangeNotifierProvider.value(value: wc),
      ],
      child: MaterialApp(theme: testTheme(themeId: theme), home: DAppConnectScreen(initialUri: uri)),
    );

SessionProposalEvent _proposal({
  int id = 1,
  VerifyContext? verify,
  String url = 'https://tpix.online',
  String name = 'TPIX TRADE',
}) =>
    SessionProposalEvent(
      id,
      ProposalData(
        id: id,
        expiry: 4102444800,
        relays: [Relay('irn')],
        proposer: ConnectionMetadata(
          publicKey: 'cd' * 32,
          metadata: PairingMetadata(name: name, description: 'TPIX TRADE DEX', url: url),
        ),
        requiredNamespaces: const {},
        optionalNamespaces: const {
          'eip155': RequiredNamespace(
            chains: ['eip155:4289', 'eip155:56', 'eip155:137', 'eip155:1'],
            methods: ['personal_sign', 'eth_sendTransaction'],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
        pairingTopic: 'ef' * 32,
      ),
      verify,
    );

VerifyContext _verify(Validation v, {String origin = 'https://tpix.online', bool? isScam}) =>
    VerifyContext(origin: origin, validation: v, verifyUrl: 'https://verify.walletconnect.org', isScam: isScam);

void main() {
  final l = LocaleProvider();

  for (final theme in [ThemeId.liquid, ThemeId.obsidian]) {
    testWidgets('จับคู่ไม่สำเร็จ (ตัวเชื่อมไม่พร้อม) → รอ init ก่อน แล้วข้อความภาษาคน ไม่ใช่ Exception ดิบ (${theme.key})',
        (tester) async {
      await tester.pumpWidget(_harness(theme, uri: _validUri));
      await tester.pump(const Duration(seconds: 5));
      // ยังรอ init อยู่ — ไม่ล้มทันที (เดิมโยน "WalletConnect not initialized" ตอนเปิดแอปเย็นจากลิงก์)
      expect(find.text(l.t('wc.pairFailed')), findsNothing);

      await tester.pump(WalletConnectService.readyTimeout);
      expect(find.text(l.t('wc.pairFailed')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('not initialized'), findsNothing);
      expect(find.textContaining('not_ready'), findsNothing);
    });

    testWidgets('wc: URI เสีย (ไม่มี symKey / QR หมดอายุ) → บอกทันที ไม่ต้องรอ (${theme.key})', (tester) async {
      await tester.pumpWidget(_harness(theme, uri: 'wc:expired@2?relay-protocol=irn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(l.t('wc.pairFailed')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    group('ที่มาของเว็บบนการ์ดคำขอเชื่อมต่อ (${theme.key})', () {
      Future<void> show(WidgetTester tester, SessionProposalEvent proposal) async {
        final wc = WalletConnectService()..debugAddProposal(proposal);
        addTearDown(wc.dispose);
        await tester.pumpWidget(_harness(theme, wc: wc));
        await tester.pump();
      }

      testWidgets('★ SCAM → เตือนแดง + ปุ่มหลักคือปฏิเสธ แต่ยังมีปุ่ม "ยังอนุมัติ"', (tester) async {
        await show(tester, _proposal(verify: _verify(Validation.SCAM, isScam: true)));

        expect(find.byKey(const ValueKey('wc-origin-warning')), findsOneWidget);
        expect(find.text(l.t('wc.originScam')), findsOneWidget);
        expect(find.text(l.t('wc.approveAnyway')), findsOneWidget);
        expect(find.text(l.t('wc.approve')), findsNothing);
        expect(find.text(l.t('wc.reject')), findsOneWidget);
        if (theme == ThemeId.obsidian) {
          final reject = tester.widget<ObsidianButton>(find.widgetWithText(ObsidianButton, l.t('wc.reject')));
          expect(reject.kind, ObsidianButtonKind.primary);
          final approve = tester.widget<ObsidianButton>(find.widgetWithText(ObsidianButton, l.t('wc.approveAnyway')));
          expect(approve.kind, ObsidianButtonKind.secondary);
          expect(approve.onPressed, isNotNull, reason: 'ผู้ใช้ยังตัดสินใจเองได้');
        }
      });

      testWidgets('★ isScam = true แม้ validation อื่น → นับเป็น SCAM', (tester) async {
        await show(tester, _proposal(verify: _verify(Validation.VALID, isScam: true)));
        expect(find.text(l.t('wc.originScam')), findsOneWidget);
      });

      testWidgets('★ INVALID → เตือนแดง (ปุ่มอนุมัติปกติ)', (tester) async {
        await show(tester, _proposal(verify: _verify(Validation.INVALID)));

        expect(find.byKey(const ValueKey('wc-origin-warning')), findsOneWidget);
        expect(find.text(l.t('wc.originInvalid')), findsOneWidget);
        expect(find.text(l.t('wc.approve')), findsOneWidget);
      });

      testWidgets('★ โดเมนที่มาไม่ตรงกับที่เว็บอ้าง → เตือนแดงพร้อมทั้งสองโดเมน', (tester) async {
        await show(tester, _proposal(verify: _verify(Validation.UNKNOWN, origin: 'https://tpix-online.xyz')));

        expect(find.byKey(const ValueKey('wc-origin-warning')), findsOneWidget);
        expect(
          find.text(l.t('wc.originMismatch').replaceAll('{origin}', 'tpix-online.xyz').replaceAll('{claimed}', 'tpix.online')),
          findsOneWidget,
        );
      });

      testWidgets('UNKNOWN / ไม่มี verify → โน้ตกลาง ๆ "ตรวจที่มาไม่ได้" ไม่ใช่คำเตือนแดง', (tester) async {
        await show(tester, _proposal(verify: null));

        expect(find.byKey(const ValueKey('wc-origin-warning')), findsNothing);
        expect(find.byKey(const ValueKey('wc-origin-unknown')), findsOneWidget);
        expect(find.text(l.t('wc.originUnknown').replaceAll('{host}', 'tpix.online')), findsOneWidget);
        expect(find.text(l.t('wc.approve')), findsOneWidget);
      });

      testWidgets('VALID + โดเมนตรง → โชว์โดเมนที่ยืนยันแล้ว', (tester) async {
        await show(tester, _proposal(verify: _verify(Validation.VALID)));

        expect(find.byKey(const ValueKey('wc-origin-verified')), findsOneWidget);
        expect(find.text(l.t('wc.originVerified').replaceAll('{host}', 'tpix.online')), findsOneWidget);
        expect(find.byKey(const ValueKey('wc-origin-warning')), findsNothing);
      });
    });
  }

  testWidgets('Obsidian: ยังไม่มีการเชื่อมต่อ → ข้อความว่าง + ปุ่มสแกนกดได้', (tester) async {
    await tester.pumpWidget(_harness(ThemeId.obsidian));
    await tester.pump();

    expect(find.text(l.t('wc.noSessions')), findsOneWidget);
    expect(find.text(l.t('obs.wc.heroTitle')), findsOneWidget);
    final scan = tester.widget<ObsidianButton>(find.byKey(const ValueKey('obs-wc-scan')));
    expect(scan.onPressed, isNotNull);
    expect(scan.loading, isFalse);
  });

  testWidgets('เปิดได้ทีละหน้า: isOpen ตามหน้าที่ mount อยู่ · ลิงก์จับคู่ใหม่ส่งให้หน้าที่เปิดอยู่', (tester) async {
    expect(DAppConnectScreen.isOpen, isFalse);
    expect(DAppConnectScreen.pairInOpenScreen(_validUri), isFalse);

    await tester.pumpWidget(_harness(ThemeId.liquid));
    expect(DAppConnectScreen.isOpen, isTrue);
    expect(DAppConnectScreen.pairInOpenScreen(_validUri), isTrue);
    await tester.pump();
    expect(find.text(l.t('wc.pairing')), findsOneWidget, reason: 'หน้าเดิมโชว์ว่ากำลังจับคู่');
    await tester.pump(WalletConnectService.readyTimeout);

    await tester.pumpWidget(const SizedBox());
    expect(DAppConnectScreen.isOpen, isFalse);
  });

  testWidgets('เปิดจากลิงก์คำขอของเว็บ แต่คำขอยังมาไม่ถึง → "กำลังรอคำขอจากเว็บ…" (ทั้งสองธีม)', (tester) async {
    for (final theme in [ThemeId.liquid, ThemeId.obsidian]) {
      final wc = WalletConnectService();
      wc.beginBrowserVisit(WcDeepLink.classify(Uri.parse('tpixwallet://wc?requestId=5'))!);
      await tester.pumpWidget(_harness(theme, wc: wc));
      await tester.pump();
      expect(find.text(l.t('wc.waitingRequest')), findsOneWidget, reason: theme.key);
      await tester.pumpWidget(const SizedBox());
      wc.dispose();
    }
  });

  group('WalletConnectService — รอ init / browser visit / คิว', () {
    testWidgets('★ pair มาก่อน init → รอได้ถึง readyTimeout แล้วโยน WalletConnectPairException', (tester) async {
      final wc = WalletConnectService();
      addTearDown(wc.dispose);
      Object? error;
      var done = false;
      wc.pair(_validUri).then<void>((_) {
        done = true;
      }, onError: (Object e) {
        error = e;
        done = true;
      });

      await tester.pump(const Duration(seconds: 10));
      expect(done, isFalse, reason: 'ยังรอ init อยู่');
      await tester.pump(const Duration(seconds: 6));
      expect(done, isTrue);
      expect(error, isA<WalletConnectPairException>());
      expect(error.toString(), isNot(contains('symKey')), reason: 'ห้ามมี URI ใน error');
    });

    testWidgets('URI เสีย → ล้มทันที ไม่รอ init', (tester) async {
      final wc = WalletConnectService();
      addTearDown(wc.dispose);
      Object? error;
      wc.pair('wc:abc@2?relay-protocol=irn').catchError((Object e) => error = e);
      await tester.pump();
      expect(error, isA<WalletConnectPairException>());
    });

    testWidgets('ลิงก์จับคู่จากเบราว์เซอร์ที่จับคู่ไม่สำเร็จ → เลิกนับว่ามาจากเบราว์เซอร์', (tester) async {
      final t0 = DateTime(2026, 10, 22, 10);
      final wc = WalletConnectService(clock: () => t0);
      addTearDown(wc.dispose);
      final link = WcDeepLink.classify(Uri.parse('tpixwallet://wc?uri=${Uri.encodeComponent(_validUri)}'))!;
      wc.beginBrowserVisit(link);
      expect(wc.awaitingBrowserProposal, isTrue);

      wc.pair((link as WcPairLink).uri).catchError((_) {});
      await tester.pump(WalletConnectService.readyTimeout + const Duration(seconds: 1));
      expect(wc.awaitingBrowserProposal, isFalse);
    });

    test('ช่วง "กำลังรอ…" หมดเองใน 30 วิ · สแกนในแอปล้างการมาจากเบราว์เซอร์ · ลิงก์เสียไม่นับ', () {
      var now = DateTime(2026, 10, 22, 10);
      final wc = WalletConnectService(clock: () => now);
      addTearDown(wc.dispose);

      wc.beginBrowserVisit(WcDeepLink.classify(Uri.parse('tpixwallet://wc?sessionTopic=${'c3' * 32}'))!);
      expect(wc.awaitingBrowserRequest, isTrue);
      now = now.add(WalletConnectService.browserWaitWindow);
      expect(wc.awaitingBrowserRequest, isFalse);

      wc.beginBrowserVisit(WcDeepLink.classify(Uri.parse('tpixwallet://wc?requestId=9'))!);
      expect(wc.awaitingBrowserRequest, isTrue);
      wc.endBrowserVisit();
      expect(wc.awaitingBrowserRequest, isFalse);

      wc.beginBrowserVisit(const WcInvalidLink());
      expect(wc.awaitingBrowserRequest, isFalse);
      expect(wc.awaitingBrowserProposal, isFalse);
    });

    test('★ คิวคำขอเชื่อมต่อ: ตัวแรกอยู่หน้า ตัวที่สองไม่ทับ · id ซ้ำไม่เข้าซ้ำ', () {
      final wc = WalletConnectService();
      addTearDown(wc.dispose);
      wc.debugAddProposal(_proposal(id: 1, name: 'A'));
      wc.debugAddProposal(_proposal(id: 2, name: 'B'));
      wc.debugAddProposal(_proposal(id: 1, name: 'A'));
      expect(wc.pendingProposal!.id, 1);
      expect(wc.hasPendingProposal, isTrue);
      // ยังไม่ได้ init → กดอนุมัติไม่ทำอะไร คิวไม่หาย
      wc.approveProposal(1);
      expect(wc.pendingProposal!.id, 1);
    });
  });
}
