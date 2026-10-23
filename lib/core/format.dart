import 'package:intl/intl.dart';

/// Display helpers. Values come from the server; these only format them.
class Fmt {
  const Fmt._();

  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final _date = DateFormat('dd MMM yyyy');
  static final _apiDate = DateFormat('yyyy-MM-dd');

  static String money(num? v) => v == null ? '–' : _money.format(v);

  static String kg(num? v) => v == null ? '–' : '${_trim(v)} kg';

  static String dateTime(DateTime? v) => v == null ? '–' : _dateTime.format(v.toLocal());

  static String date(DateTime? v) => v == null ? '–' : _date.format(v.toLocal());

  static String apiDate(DateTime v) => _apiDate.format(v);

  static String _trim(num v) {
    final s = v.toStringAsFixed(3);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
}

/// JSON readers for courier-service payloads.
num? jNum(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);

int? jInt(Object? v) => jNum(v)?.toInt();

DateTime? jTime(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? jStr(Object? v) => v is String && v.isNotEmpty ? v : null;

Map<String, dynamic> jMap(Object? v) => v is Map<String, dynamic> ? v : const {};

List<Map<String, dynamic>> jList(Object? v) => v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];
