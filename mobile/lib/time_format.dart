// Formats a backend ISO-8601 timestamp (UTC) in IST (UTC+5:30, no DST), e.g.
// "19 Sep 2026, 3:42 PM IST". Done by hand to avoid pulling in intl/timezone
// packages for one fixed offset.
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatIst(dynamic iso) {
  if (iso is! String) return 'unknown';
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final ist = parsed.toUtc().add(const Duration(hours: 5, minutes: 30));
  final hour12 = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
  final minute = ist.minute.toString().padLeft(2, '0');
  final period = ist.hour < 12 ? 'AM' : 'PM';
  return '${ist.day} ${_months[ist.month - 1]} ${ist.year}, $hour12:$minute $period IST';
}
