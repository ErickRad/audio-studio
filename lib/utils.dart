String formatMs(int ms) {
  final total = ms < 0 ? 0 : ms;
  final minutes = total ~/ 60000;
  final seconds = (total % 60000) ~/ 1000;
  final centis = (total % 1000) ~/ 10;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.${centis.toString().padLeft(2, '0')}';
}

String formatSeconds(int s) {
  final minutes = s ~/ 60;
  final seconds = s % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String shortTime(int ms) => formatMs(ms).split('.').first;
