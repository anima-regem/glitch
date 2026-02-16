import 'package:intl/intl.dart';

DateTime normalizeDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String formatReadableDate(DateTime date) {
  return DateFormat('EEE, MMM d').format(date);
}

String formatGroupDate(DateTime date) {
  return DateFormat('MMMM d, y').format(date);
}

String formatTimer(int seconds) {
  final duration = Duration(seconds: seconds);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;

  if (hours > 0) {
    final hourText = hours.toString().padLeft(2, '0');
    return '$hourText:$minutes:$secs';
  }

  return '$minutes:$secs';
}
