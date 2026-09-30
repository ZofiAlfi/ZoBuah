import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fruit_pos/features/dashboard/owner_notice_ticker.dart';
import 'package:fruit_pos/models/broadcast_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

BroadcastNotice _notice(
  String id, {
  String level = 'info',
  String title = '',
  String body = '',
}) =>
    BroadcastNotice.fromJson(level, {'id': id, 'title': title, 'body': body});

/// Bar pengumuman sudah menjadwalkan timer auto-hide 10 detik. Kalau widget-nya
/// masih terpasang saat test selesai, binding melaporkan pending timer sebagai
/// kegagalan. Melepas widget di akhir test membatalkan timer itu.
Future<void> _mount(
  WidgetTester tester,
  List<BroadcastNotice> notices,
  void Function(List<String>) onDismissed, {
  bool disableAnimations = false,
  void Function(List<String>)? onAutoHidden,
}) async {
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Column(
          children: [
            OwnerNoticeTicker(notices: notices, onDismissed: onDismissed, onAutoHidden: onAutoHidden ?? onDismissed),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Teks pengumuman berjalan terus selama bar terlihat, jadi `pumpAndSettle`
/// tidak pernah selesai. Test cukup mendorong beberapa frame supaya animasi
/// sheet sempat settles tanpa menunggu ticker ikut diam.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Bar pengumuman tipis', () {
    testWidgets('tinggi bar tetap kecil, bukan banner multi-baris',
        (tester) async {
      await _mount(
        tester,
        [_notice('n1', title: 'Diskon akhir pekan', body: 'Potongan 10%.')],
        (_) {},
      );

      final size = tester.getSize(find.byType(OwnerNoticeTicker));
      expect(size.height, OwnerNoticeTicker.barHeight);
      expect(size.height, lessThan(60));
    });

    testWidgets('judul dan isi digabung jadi satu baris', (tester) async {
      await _mount(
        tester,
        [_notice('n1', title: 'Diskon akhir pekan', body: 'Potongan 10%.')],
        (_) {},
      );

      const teks = 'Diskon akhir pekan — Potongan 10%.';
      // Teks yang tidak muat dirender dua kali supaya bisa berputar, jadi yang
      // dicek di sini isi gabungannya, bukan banyaknya widget.
      expect(find.text(teks), findsWidgets);
      // Teks panjang tidak boleh membungkus jadi banyak baris di dalam bar.
      final text = tester.widget<Text>(find.text(teks).first);
      expect(text.maxLines, 1);
    });

    testWidgets('beberapa pengumuman jadi satu bar, bukan bar bertumpuk',
        (tester) async {
      await _mount(
        tester,
        [_notice('n1', title: 'Satu'), _notice('n2', title: 'Dua')],
        (_) {},
      );

      expect(find.text('Satu   •   Dua'), findsWidgets);
      expect(find.byType(OwnerNoticeTicker), findsOneWidget);
    });

    testWidgets('label memakai level paling mendesak', (tester) async {
      await _mount(
        tester,
        [
          _notice('n1', title: 'Info biasa', level: 'info'),
          _notice('n2', title: 'Mati listrik', level: 'maintenance'),
        ],
        (_) {},
      );

      expect(find.text('PEMELIHARAAN'), findsOneWidget);
      expect(find.text('INFO'), findsNothing);
    });

    testWidgets('tanpa judul maupun isi tetap punya teks yang bisa dibaca',
        (tester) async {
      await _mount(tester, [_notice('n1')], (_) {});

      expect(find.text('Pengumuman baru'), findsWidgets);
    });
  });

  group('Auto-hide', () {
    testWidgets('bar menutup sendiri setelah 10 detik', (tester) async {
      final auto = <List<String>>[];
      final manual = <List<String>>[];
      await _mount(
        tester,
        [_notice('n1'), _notice('n2')],
        manual.add,
        onAutoHidden: auto.add,
      );

      await tester.pump(const Duration(milliseconds: 9999));
      expect(auto, isEmpty, reason: 'belum 10 detik, jangan ditutup dulu');

      await tester.pump(const Duration(milliseconds: 2));
      expect(auto, [isNotEmpty]);
      expect(auto.single, ['n1', 'n2']);
      expect(manual, isEmpty,
          reason: 'hilang sendiri bukan pilihan kasir');
    });

    testWidgets('hilang sendiri tidak disimpan sebagai sudah dibaca',
        (tester) async {
      // Kalau auto-hide ikut disimpan, pengumuman yang tidak sempat dibaca
      // kasir akan hilang permanen di perangkat ini.
      final auto = <List<String>>[];
      await _mount(
        tester,
        [_notice('n1')],
        (_) {},
        onAutoHidden: auto.add,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(auto, hasLength(1));

      expect(await OwnerNoticeTicker.dismissedIds(), isEmpty);
    });

    testWidgets('tombol tutup disimpan permanen', (tester) async {
      await _mount(tester, [_notice('n1')], (_) {});

      await tester.tap(find.byIcon(Icons.close));
      // Penutupan ditulis ke SharedPreferences secara asinkron.
      await _pumpFrames(tester);

      expect(await OwnerNoticeTicker.dismissedIds(), {'n1'});
    });

    testWidgets('bar tidak menutup sebelum waktunya', (tester) async {
      var calls = 0;
      await _mount(tester, [_notice('n1')], (_) => calls++);

      await tester.pump(const Duration(seconds: 5));
      expect(calls, 0);
    });

    testWidgets('pengumuman baru mendapat tenggat sendiri', (tester) async {
      final done = <List<String>>[];
      await _mount(tester, [_notice('n1')], done.add);
      await tester.pump(const Duration(seconds: 9));

      // Pengumuman baru masuk 1 detik sebelum tenggat pertama.
      await _mount(tester, [_notice('n1'), _notice('n2')], done.add);
      await tester.pump(const Duration(seconds: 2));
      expect(done, isEmpty, reason: 'tenggal harus dihitung ulang');

      await tester.pump(const Duration(seconds: 8));
      expect(done.single, ['n1', 'n2']);
    });
  });
  group('Interaksi', () {
    testWidgets('tombol tutup menandai semua yang tampil sebagai dibaca',
        (tester) async {
      final done = <List<String>>[];
      await _mount(tester, [_notice('n1'), _notice('n2')], done.add);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(done.single, ['n1', 'n2']);
    });

    testWidgets('menekan bar membuka isi lengkap tiap pengumuman',
        (tester) async {
      await _mount(
        tester,
        [
          _notice('n1', title: 'Diskon akhir pekan', body: 'Potongan 10%.'),
          _notice(
            'n2',
            level: 'warning',
            title: 'Mati listrik',
            body: '09.00-12.00',
          ),
        ],
        (_) {},
      );

      await tester.tap(find.byType(OwnerNoticeTicker));
      await _pumpFrames(tester);

      // Isi penuh tampil, bukan hanya potongan baris pertama.
      expect(find.text('Potongan 10%.'), findsOneWidget);
      expect(find.text('09.00-12.00'), findsOneWidget);
      expect(find.text('Mati listrik'), findsOneWidget);
      expect(find.text('Diskon akhir pekan'), findsOneWidget);
    });

    testWidgets('tombol tutup di sheet tidak dianggap sebagai selesai dibaca',
        (tester) async {
      var calls = 0;
      await _mount(tester, [_notice('n1', title: 'Judul')], (_) => calls++);

      await tester.tap(find.byType(OwnerNoticeTicker));
      await _pumpFrames(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Tutup'));
      await _pumpFrames(tester);

      expect(calls, 0);
      expect(find.byType(OwnerNoticeTicker), findsOneWidget);
    });
  });

  group('Teks berjalan', () {
    /// Lebar layar uji 800px. Teks di bawah ini sengaja dibuat jauh lebih
    /// panjang supaya tidak mungkin muat, sehingga animasi wajib menyala.
    const _panjang =
        'Pengumuman owner untuk seluruh kasir di toko ini迟早 perlu '
        'dibaca sampai habis karena isinya memang penting dan tidak boleh '
        'terlewat oleh kasir yang sedang melayani pelanggan.';

    double _geseran(WidgetTester tester) => tester
        .widget<Transform>(
          find.descendant(
            of: find.byType(OwnerNoticeTicker),
            matching: find.byType(Transform),
          ),
        )
        .transform
        .getTranslation()
        .x;

    testWidgets('teks panjang benar-benar bergerak', (tester) async {
      await _mount(tester, [_notice('n1', body: _panjang)], (_) {});
      await _pumpFrames(tester);

      final awal = _geseran(tester);
      await tester.pump(const Duration(seconds: 1));
      final akhir = _geseran(tester);

      expect(akhir, lessThan(awal),
          reason: 'teks harus berjalan ke kiri, bukan diam atau maju');
    });

    testWidgets('teks dirender dua kali supaya tidak ada jeda saat berputar',
        (tester) async {
      await _mount(tester, [_notice('n1', body: _panjang)], (_) {});
      await _pumpFrames(tester);

      expect(find.text(_panjang), findsNWidgets(2));
    });

    testWidgets('teks pendek tidak perlu bergerak', (tester) async {
      await _mount(tester, [_notice('n1', body: 'Tutup gudang jam 5')], (_) {});
      await _pumpFrames(tester);
      await tester.pump(const Duration(seconds: 1));

      // Teks muat, jadi tidak ada Transform yang menggesernya.
      expect(
        find.descendant(
          of: find.byType(OwnerNoticeTicker),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(find.text('Tutup gudang jam 5'), findsOneWidget);
    });
  });

  group('Aksesibilitas', () {
    testWidgets('reduce motion mematikan teks berjalan', (tester) async {
      await _mount(
        tester,
        [
          _notice(
            'n1',
            body: 'Pengumuman yang sangat panjang sekali agar pasti tidak '
                'muat di lebar layar pengujian dan harusnya berjalan terus '
                'kalau animasi menyala.',
          ),
        ],
        (_) {},
        disableAnimations: true,
      );
      await tester.pump(const Duration(seconds: 2));

      // Teks yang tidak muat dipotong dengan elipsis, bukan tetap berjalan.
      final running = tester.widget<Text>(
        find.descendant(
          of: find.byType(OwnerNoticeTicker),
          matching: find.byType(Text),
        ).last,
      );
      expect(running.overflow, TextOverflow.ellipsis);
    });

    testWidgets('target sentuh tombol tutup minimal 44px', (tester) async {
      await _mount(tester, [_notice('n1')], (_) {});

      final button = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.width, greaterThanOrEqualTo(44));
      expect(button.height, greaterThanOrEqualTo(44));
    });

    testWidgets('tombol tutup punya label untuk pembaca layar',
        (tester) async {
      await _mount(tester, [_notice('n1')], (_) {});

      expect(find.byTooltip('Tutup pengumuman'), findsOneWidget);
    });
  });
}
