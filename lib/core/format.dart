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

/// Formats Philippine Peso values (e.g., 1234.5 -> "PHP 1,234.50").
String formatPhp(double v) {
  if (!v.isFinite) return 'Unverified';
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return 'PHP $whole.${parts[1]}';
}

/// Legacy alias kept for existing callers and tests.
String rm(double v) => formatPhp(v);

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

String pluralize(int count, String singular, [String? plural]) {
  if (count == 1) return singular;
  return plural ?? '${singular}s';
}

/// Pluralizes item unit labels from the backend (e.g. 50 "roll" -> "rolls").
String formatUnit(int count, String unit) {
  final trimmed = unit.trim();
  if (trimmed.isEmpty) return '';
  if (count == 1) return trimmed;
  final lower = trimmed.toLowerCase();
  if (lower.endsWith('s')) return trimmed;
  if (lower.endsWith('x') || lower.endsWith('ch') || lower.endsWith('sh')) {
    return '${trimmed}es';
  }
  return '${trimmed}s';
}

/// Normalizes "truck - ABC-1234" into "Truck · ABC-1234".
String formatVehicle(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final parts = trimmed.split(RegExp(r'\s+-\s+'));
  if (parts.length == 2) {
    final kind = parts[0].trim();
    final capKind = kind.isEmpty
        ? kind
        : '${kind[0].toUpperCase()}${kind.substring(1)}';
    return '$capKind · ${parts[1].trim()}';
  }
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
}

/// Formats Philippine/local phone strings legibly without altering raw digits
/// used for `tel:` dialing.
String formatPhoneDisplay(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 12 && digits.startsWith('63')) {
    return '+63 ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
  }
  return trimmed;
}

/// Shortens long machine-generated hash IDs (e.g. "OG-bf9ddc112c51452e8b77")
/// into scannable references while keeping human-readable IDs intact.
String shortRef(String raw) {
  final trimmed = raw.trim();
  if (trimmed.length <= 14) return trimmed;
  return '${trimmed.substring(0, 9)}…${trimmed.substring(trimmed.length - 4)}';
}

String formatDistance(double meters) {
  if (!meters.isFinite || meters < 0) return '';
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return km >= 10 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km';
}

String formatDuration(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '';
  final minutes = (seconds / 60).round().clamp(1, 9999);
  if (minutes < 60) return '~$minutes min';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  return rem == 0 ? '~${hours}h' : '~${hours}h ${rem}m';
}

String formatInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'HY';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
