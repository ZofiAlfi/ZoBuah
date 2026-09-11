import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fruit_pos/main.dart' as app;

Future<void> _waitCondition(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 500));
    if (condition()) return;
  }
  throw StateError('Timeout menunggu kondisi: benar tidak pernah tercapai');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('POS di perangkat: tap produk masuk keranjang', (tester) async {
    app.main();

    final mulai = find.text('Mulai Penjualan');
    final masuk = find.text('MASUK');
    await _waitCondition(
      tester,
      () => mulai.evaluate().isNotEmpty || masuk.evaluate().isNotEmpty,
    );

    if (masuk.evaluate().isNotEmpty) {
      await tester.enterText(
          find.widgetWithText(TextField, 'Username'), 'aab');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'aab12345');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(masuk);
    }

    await _waitCondition(tester, () => mulai.evaluate().isNotEmpty);

    await tester.tap(find.text('Mulai Penjualan'));
    await _waitCondition(tester, () => find.byType(GridView).evaluate().isNotEmpty);

    final tile = find
        .descendant(of: find.byType(GridView), matching: find.byType(InkWell))
        .first;
    expect(tile, findsOneWidget);
    await tester.tap(tile, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('BAYAR'), findsOneWidget);
  });
}