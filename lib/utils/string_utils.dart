String formatEnumString(String s) {
  if (s.isEmpty) return s;
  return s
      .split('_')
      .map((word) {
        if (word.isEmpty) return '';
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      })
      .join(' ');
}
