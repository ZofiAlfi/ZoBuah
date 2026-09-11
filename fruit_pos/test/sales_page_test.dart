import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fruit_pos/features/sales/sales_page.dart';
import 'package:fruit_pos/models/product.dart';

const _fujiBtn = ValueKey('prod_p1');

Product _apelFuji() => Product(
  id: 'p1',
  name: 'Apel Fuji',
  unit: 'kg',
  modalPrice: 12000,
  sellingPrice: 18000,
  stock: 28,
  minStock: 5,
  isActive: true,
);

Future<void> _openAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(_fujiBtn));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('qty_dialog')), findsOneWidget);
  await tester.tap(find.byKey(const Key('qty_add')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tap produk membuka dialog jumlah lalu menambah item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1576);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SalesPage(productsLoader: (_) async => [_apelFuji()])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apel Fuji'), findsOneWidget);
    expect(find.byKey(const Key('checkout')), findsNothing);

    await tester.tap(find.byKey(_fujiBtn));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qty_dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('qty_add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkout')), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('Total Harga'), findsOneWidget);
    expect(find.text('1 kg'), findsOneWidget);
  });

  testWidgets('tap dua kali (via dialog) menambah jumlah item', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SalesPage(productsLoader: (_) async => [_apelFuji()])),
    );
    await tester.pumpAndSettle();

    await _openAndConfirm(tester);
    await _openAndConfirm(tester);

    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('2 kg'), findsOneWidget);
    expect(find.text('Rp 36.000'), findsNWidgets(2));
  });

  testWidgets('tombol kosongkan membersihkan keranjang', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SalesPage(productsLoader: (_) async => [_apelFuji()])),
    );
    await tester.pumpAndSettle();

    await _openAndConfirm(tester);
    expect(find.byKey(const Key('checkout')), findsOneWidget);

    await tester.tap(find.byTooltip('Kosongkan keranjang'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkout')), findsNothing);
  });

  testWidgets('produk per kg bisa memakai jumlah pecahan', (tester) async {
    tester.view.physicalSize = const Size(720, 1576);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: SalesPage(productsLoader: (_) async => [_apelFuji()])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_fujiBtn));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qty_dialog')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('qty_field')), '0.75');
    await tester.pumpAndSettle();
    expect(find.text('Rp 13.500'), findsOneWidget);

    await tester.tap(find.byKey(const Key('qty_add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkout')), findsOneWidget);
    expect(find.text('0.75 kg'), findsOneWidget);
    expect(find.text('Rp 13.500'), findsNWidgets(2));
  });

  testWidgets('produk bukan timbangan pakai jumlah bulat tanpa chip', (
    tester,
  ) async {
    Product kelapa() => Product(
      id: 'p2',
      name: 'Kelapa Tua',
      unit: 'buah',
      modalPrice: 7000,
      sellingPrice: 10000,
      stock: 12,
      minStock: 2,
      isActive: true,
    );

    await tester.pumpWidget(
      MaterialApp(home: SalesPage(productsLoader: (_) async => [kelapa()])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('prod_p2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('qty_dialog')), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.enterText(find.byKey(const Key('qty_field')), '3');
    await tester.tap(find.byKey(const Key('qty_add')));
    await tester.pumpAndSettle();

    expect(find.text('3 buah'), findsOneWidget);
    expect(find.text('Rp 30.000'), findsNWidgets(2));
  });
}