const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// 2026-01-12 -> "12 ene 2026" (no `intl` dependency needed for this).
String formatShortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]} ${date.year}';

String _two(int n) => n.toString().padLeft(2, '0');

/// 2026-01-12 -> the API's ISO date.
String apiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

/// "2026-01-12" -> local midnight of that day.
DateTime parseApiDate(String iso) => DateTime.parse(iso.substring(0, 10));

/// The API sends naive timestamps (no zone); they are UTC. Returned in local time.
DateTime parseApiDateTime(String iso) {
  final hasZone = iso.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(iso);
  return DateTime.parse(hasZone ? iso : '${iso}Z').toLocal();
}

/// Decimal comma, as users read numbers here: 0.77 -> "0,77".
String decimal(double value, int digits) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

/// "12 ene 2026 · 14:32"
String formatDateTime(DateTime date) =>
    '${formatShortDate(date)} · ${_two(date.hour)}:${_two(date.minute)}';
