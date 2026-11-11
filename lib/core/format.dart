const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String fmtDate(DateTime d) =>
    '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
String fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String fmtWhen(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, ${fmtTime(d)}';
  if (diff == 1) return 'Yesterday, ${fmtTime(d)}';
  return '${d.day} ${_months[d.month - 1].substring(0, 3)}, ${fmtTime(d)}';
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

/// 1234.5 -> "RM 1,234.50"
String rm(double v) {
  if (!v.isFinite) return "Unverified";
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return 'PHP $whole.${parts[1]}';
}

/// Readable schedule labels always use Manila, regardless of phone timezone.
String manilaSchedule(DateTime? value) {
  if (value == null) return 'Schedule unavailable';
  final day = value.toUtc().add(const Duration(hours: 8));
  final today = DateTime.now().toUtc().add(const Duration(hours: 8));
  final date =
      day.year == today.year && day.month == today.month && day.day == today.day
      ? 'Today'
      : '${day.day} ${_months[day.month - 1].substring(0, 3)}${day.year == today.year ? '' : ' ${day.year}'}';
  final hour = day.hour % 12 == 0 ? 12 : day.hour % 12;
  return '$date, $hour:${day.minute.toString().padLeft(2, '0')} ${day.hour < 12 ? 'AM' : 'PM'}';
}
