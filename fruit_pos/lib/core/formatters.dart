import 'package:intl/intl.dart';

class Formatters {
  static final NumberFormat _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static final NumberFormat _decimal = NumberFormat('#,##0.###', 'id_ID');

  static String currency(num value) => _rupiah.format(value.toDouble());

  static String decimal(num value) => _decimal.format(value.toDouble());

  static String quantity(num value) {
    final v = value.toDouble();
    if (v == v.roundToDouble()) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static String date(DateTime? dt) {
    if (dt == null) return '-';
    try {
      return DateFormat('dd MMM yyyy', 'id_ID').format(dt.toLocal());
    } catch (_) {
      return '${dt.day}-${dt.month}-${dt.year}';
    }
  }

  static String dateTime(DateTime? dt) {
    if (dt == null) return '-';
    try {
      return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(dt.toLocal());
    } catch (_) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}-${dt.month}-${dt.year} $h:$m';
    }
  }

  static String time(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('HH:mm', 'id_ID').format(dt.toLocal());
  }

  static String transNo(String raw) => raw;
}