/// Returns a new list sorted by [sortKey] (case-insensitive).
/// Stable: ties keep their input order (List.sort alone is not stable).
List<dynamic> sortSongsByKey(List<dynamic> songs, String sortKey) {
  String keyOf(dynamic song) =>
      (song is Map ? song[sortKey] ?? '' : '').toString().toLowerCase();

  final indexed =
      [for (var i = 0; i < songs.length; i++) (index: i, key: keyOf(songs[i]))]
        ..sort((a, b) {
          final byKey = a.key.compareTo(b.key);
          return byKey != 0 ? byKey : a.index.compareTo(b.index);
        });
  return [for (final entry in indexed) songs[entry.index]];
}

/// Returns a new list with the most recently appended songs first.
List<dynamic> sortSongsNewestFirst(List<dynamic> songs) =>
    List<dynamic>.of(songs.reversed);

/// Returns a new list ordered by newest [dateKey], preserving ties.
List<dynamic> sortSongsByDateAdded(
  List<dynamic> songs, {
  String dateKey = 'dateAdded',
}) {
  int dateOf(dynamic song) {
    final value = song is Map ? song[dateKey] : null;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  final indexed =
      [
        for (var i = 0; i < songs.length; i++)
          (index: i, date: dateOf(songs[i])),
      ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : a.index.compareTo(b.index);
      });
  return [for (final entry in indexed) songs[entry.index]];
}
