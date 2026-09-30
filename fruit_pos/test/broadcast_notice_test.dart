import 'package:flutter_test/flutter_test.dart';
import 'package:fruit_pos/features/dashboard/owner_notice_ticker.dart';
import 'package:fruit_pos/models/broadcast_notice.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BroadcastNotice', () {
    // Server mengirim waktu UTC tanpa suffix Z. Kalau string ini dibaca sebagai
    // waktu lokal, jamnya bergeser sebesar selisih zona waktu, jadi pengumuman
    // bisa hilang jauh sebelum waktunya atau bertahan setelahnya.
    test('waktu tanpa suffix Z dibaca sebagai UTC', () {
      final notice = BroadcastNotice.fromJson('info', {
        'id': 'a1',
        'title': 'Diskon akhir pekan',
        'body': 'Diskon 10%.',
        'starts_at': '2026-09-28T02:53:40.738865',
        'expires_at': '2026-09-30T02:53:40.738865',
      });

      // Dibandingkan lewat toUtc() supaya hasilnya benar di zona waktu mesin
      // mana pun, bukan hanya di mesin yang kebetulan memakai UTC.
      expect(notice.startsAt!.toUtc(), DateTime.utc(2026, 9, 28, 2, 53, 40, 738, 865));
      expect(notice.expiresAt!.toUtc(), DateTime.utc(2026, 9, 30, 2, 53, 40, 738, 865));
    });

    test('waktu ber-suffix Z tetap benar', () {
      final notice = BroadcastNotice.fromJson('warning', {
        'id': 'a2',
        'starts_at': '2026-09-28T02:53:40.738Z',
      });
      expect(notice.startsAt!.toUtc(), DateTime.utc(2026, 9, 28, 2, 53, 40, 738));
    });

    test('waktu dengan offset eksplisit dihormati', () {
      final notice = BroadcastNotice.fromJson('info', {
        'id': 'a3',
        'starts_at': '2026-09-28T09:53:40.738+07:00',
      });
      expect(notice.startsAt!.toUtc(), DateTime.utc(2026, 9, 28, 2, 53, 40, 738));
    });

    test('waktu kosong atau rusak tidak membuat crash', () {
      final notice = BroadcastNotice.fromJson('info', {'id': 'a4', 'starts_at': 'bukan tanggal'});
      expect(notice.startsAt, isNull);
      expect(notice.title, isEmpty);
      expect(notice.id, 'a4');
    });

    test('level non-biasa dianggap mendesak', () {
      expect(BroadcastNotice.fromJson('warning', const {}).isUrgent, isTrue);
      expect(BroadcastNotice.fromJson('maintenance', const {}).isUrgent, isTrue);
      expect(BroadcastNotice.fromJson('info', const {}).isUrgent, isFalse);
    });

    test('toMap lalu fromMap mengubah waktu tanpa geser', () {
      final asli = BroadcastNotice.fromJson('info', {
        'id': 'a5',
        'title': 'Judul',
        'body': 'Isi',
        'starts_at': '2026-09-28T02:53:40.738865',
        'expires_at': '2026-09-30T02:53:40.738865',
      });

      final kembali = BroadcastNotice.fromMap('info', asli.toMap());

      expect(kembali.id, 'a5');
      expect(kembali.title, 'Judul');
      expect(kembali.body, 'Isi');
      expect(kembali.startsAt!.toUtc(), asli.startsAt!.toUtc());
      expect(kembali.expiresAt!.toUtc(), asli.expiresAt!.toUtc());
    });
  });

  group('Penutupan pengumuman', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('id yang ditutup tersimpan dan ikut dibaca kembali', () async {
      await OwnerNoticeTicker.markDismissed('b1');
      await OwnerNoticeTicker.markDismissed('b2');

      expect(await OwnerNoticeTicker.dismissedIds(), {'b1', 'b2'});
    });

    test('menutup pengumuman lain tidak menghapus yang lama', () async {
      await OwnerNoticeTicker.markDismissed('b1');
      await OwnerNoticeTicker.markDismissed('b2');

      // Dipanggil lagi setelah app start ulang.
      expect(await OwnerNoticeTicker.dismissedIds(), {'b1', 'b2'});
    });

    test('id kosong diabaikan', () async {
      await OwnerNoticeTicker.markDismissed('');

      expect(await OwnerNoticeTicker.dismissedIds(), isEmpty);
    });

    test('pref kosong dibaca sebagai daftar kosong', () async {
      expect(await OwnerNoticeTicker.dismissedIds(), isEmpty);
    });
  });
}
