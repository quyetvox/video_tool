class AnsiStripUtils {
  static final RegExp _ansiRegex = RegExp(r'\x1B\[[0-9;]*[a-zA-K]');

  /// Strip ANSI escape sequences from terminal log text
  static String stripAnsi(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(_ansiRegex, '');
  }
}
