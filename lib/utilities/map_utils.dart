import 'dart:math';

Map<String, dynamic> cloneMap(Map source) {
  return Map<String, dynamic>.from(source);
}

List<Map<String, dynamic>> cloneMaps(Iterable<Map> sources) {
  return sources.map(cloneMap).toList();
}

String? songYtid(Map song) {
  final ytid = song['ytid']?.toString();
  return ytid == null || ytid.isEmpty ? null : ytid;
}

Map? findSongByYtid(Iterable<dynamic> songs, String ytid) {
  for (final song in songs) {
    if (song is Map && songYtid(song) == ytid) return song;
  }
  return null;
}

List<Map> sampleUniqueSongs(
  Iterable<Iterable<dynamic>> sources,
  int count, {
  Random? random,
}) {
  if (count <= 0) return const [];

  final sampler = random ?? Random();
  final seenYtids = <String>{};
  final reservoir = <Map>[];
  var uniqueSongCount = 0;

  for (final source in sources) {
    for (final song in source) {
      if (song is! Map) continue;
      final ytid = songYtid(song);
      if (ytid == null || !seenYtids.add(ytid)) continue;

      uniqueSongCount++;
      if (reservoir.length < count) {
        reservoir.add(song);
      } else {
        final slot = sampler.nextInt(uniqueSongCount);
        if (slot < count) reservoir[slot] = song;
      }
    }
  }

  reservoir.shuffle(sampler);
  return reservoir;
}
