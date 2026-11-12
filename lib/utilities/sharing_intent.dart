import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/utilities/formatter.dart';

final _youtubeLinkRegex = RegExp(r'(youtube\.com|youtu\.be)');

Future<void> handleYoutubeSharedTextIntent(
  String? value, {
  required MusifyAudioHandler audioHandler,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  if (value == null || !_youtubeLinkRegex.hasMatch(value)) {
    return;
  }

  final songId = getSongId(value);
  if (songId == null) {
    return;
  }

  try {
    final song = await getSongDetails(0, songId);
    await audioHandler.playSong(song);
  } catch (e, stackTrace) {
    onError(e, stackTrace);
  }
}

Future<void> consumeYoutubeSharedTextIntent(
  String? value, {
  required MusifyAudioHandler audioHandler,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  if (value == null || value.isEmpty) {
    return;
  }

  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty) {
    return;
  }

  await handleYoutubeSharedTextIntent(
    normalizedValue,
    audioHandler: audioHandler,
    onError: onError,
  );
}
