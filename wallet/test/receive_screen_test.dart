/// TPIX Wallet — เทสต์หน้ารับเงิน
///
/// บั๊กที่เคยเกิด (ทำให้ผู้ใช้บอกว่า "เปิดหน้ารับเงินแล้วไม่มีอะไรเลย"):
/// 1. สีตัวอักษรฮาร์ดโค้ด Colors.white → พอสลับไปธีมสว่างกลายเป็นขาวบนขาว
/// 2. ยังไม่มีกระเป๋า (address ว่าง) ก็ยังวาด QR ของสตริงว่าง ซึ่งสแกนไปไม่ได้อะไร
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tpix_wallet/core/locale_provider.dart';
import 'package:tpix_wallet/providers/wallet_provider.dart';
import 'package:tpix_wallet/screens/receive_screen.dart';

import 'support/test_theme.dart';

/// ความสว่างโดยประมาณ 0 (ดำ) .. 1 (ขาว)
double _luminance(Color c) => c.computeLuminance();

Widget _harness({required ThemeData theme}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => WalletProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(theme: theme, home: const ReceiveScreen()),
  );
}

void main() {
  testWidgets('ธีมสว่าง: ตัวอักษรต้องอ่านออก ไม่ใช่ขาวบนขาว', (tester) async {
    await tester.pumpWidget(_harness(theme: testTheme(dark: false)));
    await tester.pump();

    // เก็บสีของข้อความทุกตัวบนหน้า
    final texts = tester.widgetList<Text>(find.byType(Text));
    expect(texts, isNotEmpty);

    final invisible = <String>[];
    for (final t in texts) {
      final color = t.style?.color;
      if (color == null) continue; // ใช้สีจากธีม = ปลอดภัยอยู่แล้ว
      // พื้นหลังธีมสว่างสว่างมาก (>0.8) → ตัวอักษรที่สว่างพอกันคืออ่านไม่ออก
      if (_luminance(color) > 0.75) {
        invisible.add('"${t.data}" → $color');
      }
    }

    expect(invisible, isEmpty,
        reason: 'ข้อความสีสว่างบนพื้นสว่าง = มองไม่เห็น:\n${invisible.join("\n")}');
  });

  testWidgets('ยังไม่มีกระเป๋า → บอกให้สร้างกระเป๋า ไม่ใช่โชว์ QR เปล่า',
      (tester) async {
    await tester.pumpWidget(_harness(theme: testTheme()));
    await tester.pump();

    // WalletProvider ที่เพิ่งสร้างยังไม่มีที่อยู่ → ต้องไม่มี QR
    expect(find.byType(QrImageView), findsNothing,
        reason: 'ไม่มีที่อยู่แล้วยังวาด QR = QR ของสตริงว่าง สแกนไปก็ไม่ได้อะไร');

    final l = LocaleProvider();
    expect(find.text(l.t('receive.noWallet')), findsOneWidget);
  });
}
