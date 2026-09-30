import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../models/broadcast_notice.dart';

/// Bar pengumuman owner di atas halaman POS.
///
/// Bar ini sengaja dibuat setipis mungkin: satu baris, teks berjalan
/// horizontal, hilang sendiri setelah [visibleFor]. Versi sebelumnya memakai
/// banner multi-baris berisi judul dan isi, yang mendorong layar kasir ke bawah
/// dan menutupi area tempat kasir menekan tombol.
///
/// Semua pengumuman yang belum ditutup digabung jadi satu baris, jadi notifikasi
/// yang menumpuk tidak membuat bar bertambah tinggi. Teks lengkapnya tetap bisa
/// dibaca lewat dialog detail saat bar ditekan.
///
/// Widget ini tidak menyimpan daftar mana yang sudah ditutup. Penutupan
/// dikembalikan lewat [onFinished] supaya pemilik widget bisa memutuskan
/// pengumuman mana yang dianggap selesai: kalau penyimpanannya sendiri,
/// menutup pengumuman atas hanya akan membuat bar hilang dan pengumuman di
/// bawahnya tidak pernah muncul.
class OwnerNoticeTicker extends StatefulWidget {
  final List<BroadcastNotice> notices;

  /// Dipanggil saat bar hilang sendiri. Pengumuman hanya disembunyikan untuk
  /// sesi ini dan TIDAK disimpan, jadi pengumuman yang tidak sempat dibaca
  /// kasir akan muncul lagi di app start berikutnya.
  final void Function(List<String> ids) onAutoHidden;

  /// Dipanggil saat kasir menekan tombol tutup. Pengumuman dianggap selesai
  /// dibaca dan disimpan permanen lewat [markDismissed].
  final void Function(List<String> ids) onDismissed;
  const OwnerNoticeTicker({
    super.key,
    required this.notices,
    required this.onAutoHidden,
    required this.onDismissed,
  });

  /// Lama bar tetap terlihat sebelum menutup sendiri.
  static const visibleFor = Duration(seconds: 10);

  /// Tinggi bar. Tombol tutup memakai target sentuh 44px, jadi bar dibuat
  /// setinggi target itu, bukan lebih tipis, supaya tetap mudah ditekan.
  static const barHeight = 44.0;

  static const dismissedKey = 'owner_notice_dismissed_ids';

  /// Daftar id yang sudah ditutup, untuk dipakai kembali setelah app start.
  static Future<Set<String>> dismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(dismissedKey) ?? const []).toSet();
  }

  /// Tandai pengumuman sudah selesai dibaca.
  ///
  /// Disimpan per id, jadi pengumuman baru tetap muncul walaupun pengumuman
  /// lama sudah ditutup.
  static Future<void> markDismissed(String id) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = (prefs.getStringList(dismissedKey) ?? const []).toSet()
      ..add(id);
    await prefs.setStringList(dismissedKey, dismissed.toList());
  }

  @override
  State<OwnerNoticeTicker> createState() => _OwnerNoticeTickerState();
}

class _OwnerNoticeTickerState extends State<OwnerNoticeTicker> {
  Timer? _autoHide;

  @override
  void initState() {
    super.initState();
    _scheduleAutoHide();
  }

  @override
  void didUpdateWidget(covariant OwnerNoticeTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pengumuman baru yang masuk di tengah bar berjalan harus mendapat
    // jendela baca sendiri, kalau tidak ia akan hilang hanya karena bar yang
    // lain kebetulan sedang hampir kedaluwarsa.
    if (oldWidget.notices.length != widget.notices.length) {
      _scheduleAutoHide();
    }
  }

  @override
  void dispose() {
    _autoHide?.cancel();
    super.dispose();
  }

  void _scheduleAutoHide() {
    _autoHide?.cancel();
    if (widget.notices.isEmpty) return;
    _autoHide = Timer(OwnerNoticeTicker.visibleFor, () {
      final ids = _ids();
      if (ids.isEmpty) return;
      widget.onAutoHidden(ids);
    });
  }

  List<String> _ids() => {for (final n in widget.notices) n.id}.toList();

  void _dismiss() {
    final ids = _ids();
    if (ids.isEmpty) return;
    // Menutup dengan tangan berarti kasir sudah membaca pengumuman itu, jadi
    // disimpan permanen lewat [markDismissed]. Bar yang hilang sendiri tidak
    // lewat sini: kalau ikut disimpan, pengumuman yang tidak sempat dibaca
    // tidak akan pernah muncul lagi di perangkat ini.
    for (final id in ids) {
      unawaited(OwnerNoticeTicker.markDismissed(id));
    }
    widget.onDismissed(ids);
  }

  /// Level paling mendesak menentukan warna dan label, supaya pengumuman
  /// 'Penting' tidak tersamar di belakang pengumuman 'Info' yang lebih dulu.
  BroadcastNotice get _topNotice {
    var top = widget.notices.first;
    for (final n in widget.notices.skip(1)) {
      if (n.isUrgent && !top.isUrgent) top = n;
    }
    return top;
  }

  static String _lineOf(BroadcastNotice n) {
    final parts =
        [n.title.trim(), n.body.trim()].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'Pengumuman baru';
    return parts.join(' — ');
  }

  Future<void> _openDetail() async {
    final notices = List<BroadcastNotice>.of(widget.notices);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _NoticeDetailSheet(notices: notices),
    );
    // Menutup sheet tidak membatalkan auto-hide. Kalau kasir menekan bar
    // tepat sebelum tenggat, pengumuman yang baru saja dibaca tidak boleh
    // langsung hilang tanpa waktu baca tambahan.
    if (mounted) _scheduleAutoHide();
  }

  @override
  Widget build(BuildContext context) {
    final level = _topNotice.level;
    final accent = _accentFor(level);
    final label = _labelFor(level);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      color: accent.withValues(alpha: 0.10),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: _openDetail,
          child: SizedBox(
            height: OwnerNoticeTicker.barHeight,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: OwnerNoticeTicker.barHeight,
                  color: accent,
                ),
                const SizedBox(width: 10),
                Icon(_iconFor(level), size: 14, color: accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RunningText(
                    text: widget.notices.map(_lineOf).join('   •   '),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      height: 1.2,
                    ),
                    animate: !reduceMotion,
                  ),
                ),
                if (widget.notices.length > 1)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.notices.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Tutup pengumuman',
                  onPressed: _dismiss,
                  icon: Icon(Icons.close, size: 16, color: accent),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _accentFor(String level) => switch (level) {
        'maintenance' => AppColors.warning,
        'warning' => AppColors.danger,
        _ => AppColors.info,
      };

  static String _labelFor(String level) => switch (level) {
        'maintenance' => 'PEMELIHARAAN',
        'warning' => 'PENTING',
        _ => 'INFO',
      };

  static IconData _iconFor(String level) => switch (level) {
        'maintenance' => Icons.build_circle_outlined,
        'warning' => Icons.warning_amber_rounded,
        _ => Icons.campaign_outlined,
      };
}

/// Dialog isi lengkap untuk pengumuman yang tidak muat di bar berjalan.
class _NoticeDetailSheet extends StatelessWidget {
  final List<BroadcastNotice> notices;

  const _NoticeDetailSheet({required this.notices});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Pengumuman owner',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                itemCount: notices.length,
                separatorBuilder: (_, _) => const Divider(height: 24),
                itemBuilder: (context, i) {
                  final n = notices[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _OwnerNoticeTickerState._labelFor(n.level),
                        style: TextStyle(
                          color: _OwnerNoticeTickerState._accentFor(n.level),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (n.title.trim().isNotEmpty)
                        Text(
                          n.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (n.body.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            n.body,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Teks satu baris yang berjalan horizontal kalau tidak muat.
///
/// Lebar teks diukur dengan [TextPainter] memakai style yang sama persis dengan
/// teks yang dirender. Kalau muat, teks diam dan tidak ada animasi sama sekali:
/// gerak tanpa alasan hanya menambah beban mata kasir.
class _RunningText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool animate;

  const _RunningText({
    required this.text,
    required this.style,
    required this.animate,
  });

  @override
  State<_RunningText> createState() => _RunningTextState();
}

class _RunningTextState extends State<_RunningText>
    with SingleTickerProviderStateMixin {
  /// Jarak antara dua salinan teks, jadi teks tidak terlihat terpotong saat
  /// menyeberang.
  static const _gap = 48.0;

  /// Diinisialisasi di [initState], bukan sebagai `late final` yang lazily
  /// dibuat saat pertama kali diakses. Kalau teksnya muat dan controller
  /// tidak pernah tersentuh, initialize saat [dispose] akan mencari Ticker
  /// pada pohon yang sudah dinonaktifkan dan melempar assertion.
  late final AnimationController _controller;

  /// Lebar viewport dari frame terakhir, untuk membandingkan lebar teks.
  double? _available;

  /// Lebar satu salinan teks, diukur dari widget yang benar-benar dirender.
  double? _copyWidth;

  /// Panjang satu siklus geseran, null kalau teksnya muat sehingga tidak
  /// perlu animasi.
  double? _loop;

  /// Lebar diukur dari widget yang sedang tampil.
  ///
  /// Lebar teks diukur dari render tree, bukan dari TextPainter: hasil
  /// TextPainter bisa berbeda dari teks yang benar-benar dirender, lalu
  /// container salah setback dan teks ikut terpotong. Hanya salah satu dari
  /// dua widget ini yang ada pada satu waktu, jadi [_measuredWidth] menormalkan
  /// keduanya ke lebar satu salinan teks.
  final GlobalKey _staticKey = GlobalKey();
  final GlobalKey _rowKey = GlobalKey();

  /// Berapa milidetik per satu siklus yang sedang berjalan, disimpan sendiri
  /// karena AnimationController tidak mengekspos perioda aktifnya.
  Duration? _runningPeriod;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _RunningText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Teks atau mode animasi berubah, lebar harus diukur ulang.
    if (oldWidget.text != widget.text ||
        oldWidget.animate != widget.animate) {
      _measureAfterFrame();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Lebar satu salinan teks dari widget yang sedang terlayout, atau null
  /// kalau belum ada yang bisa diukur.
  double? _measuredWidth() {
    final statis = _staticKey.currentContext?.size?.width;
    if (statis != null) return statis;
    final row = _rowKey.currentContext?.size?.width;
    if (row == null) return null;
    // Baris berjalan berisi [teks, _gap, teks].
    return (row - _gap) / 2;
  }

  void _applyLoop(double? loop) {
    if (loop == null) {
      if (_controller.isAnimating) {
        _controller.stop();
        _controller.value = 0;
      }
      _runningPeriod = null;
      return;
    }
    // Kecepatan konstan sekitar 45px/detik, jadi teks yang lebih panjang butuh
    // waktu lebih banyak dan tidak terburu-buru dibaca.
    final period = Duration(milliseconds: ((loop * 22).clamp(6000, 45000)).toInt());
    if (_runningPeriod == period && _controller.isAnimating) return;
    _runningPeriod = period;
    _controller.repeat(period: period);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_available != constraints.maxWidth) {
          _available = constraints.maxWidth;
          _measureAfterFrame();
        }
        return ClipRect(child: _content());
      },
    );
  }

  /// Mengukur setelah frame selesai, lalu memulai atau menghentikan animasi.
  ///
  /// AnimationController notifying pendengarnya saat masih di tengah layout
  /// bisa memicu build di tengah frame, jadi semua perubahan state ditunda ke
  /// frame berikutnya.
  void _measureAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final width = _measuredWidth();
      if (width == null || width <= 0) return;
      final wasAnimating = _loop != null;
      final available = _available;
      final shouldAnimate =
          widget.animate && available != null && width > available - 1;
      if (width == _copyWidth && shouldAnimate == wasAnimating) return;

      setState(() {
        _copyWidth = width;
        _loop = shouldAnimate ? width + _gap : null;
      });
      _applyLoop(_loop);

      // Sumber pengukuran berganti antara teks tunggal dan baris ganda saat
      // animasi mulai atau berhenti, jadi ukur sekali lagi untuk memastikan
      // lebarnya sudah benar-benar sesuai.
      if (shouldAnimate != wasAnimating) _measureAfterFrame();
    });
  }

  Widget _content() {
    final loop = _loop;
    if (loop == null) {
      return Text(
        widget.text,
        key: _staticKey,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Teks dirender dua kali berdampingan, lalu baris itu digeser satu siklus
    // sebesar satu teks plus satu jarak. Saat melewati tepi kanan, salinan
    // berikutnya sudah bersiap di sebelah kiri, jadi tidak ada teks yang
    // terlihat terpotong di tengah.
    //
    // Row-nya dibungkus OverflowBox supaya lebarnya bebas mengikuti isi, bukan
    // dibatasi lebar bar. Tanpa itu Flutter menandai bar sebagai melimpah,
    // padahal seluruh kelimpsetnya memang disengaja dan sudah dipotong
    // ClipRect di atas.
    final content = OverflowBox(
      alignment: Alignment.centerLeft,
      minWidth: 0,
      maxWidth: double.infinity,
      child: Row(
        key: _rowKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.text,
              style: widget.style, maxLines: 1, softWrap: false),
          const SizedBox(width: _gap),
          Text(widget.text,
              style: widget.style, maxLines: 1, softWrap: false),
        ],
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      child: content,
      builder: (context, child) => Transform.translate(
        offset: Offset(-_controller.value * loop, 0),
        child: child,
      ),
    );
  }
}