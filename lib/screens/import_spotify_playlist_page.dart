import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/artist_service.dart' show ytMusicClient;
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/formatter.dart';
import 'package:musify/utilities/media_duration.dart';
import 'package:musify/utilities/url_launcher.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A CSV row and its original position, used to preserve playlist order.
typedef _ImportRow = ({
  int index,
  String title,
  String artist,
  int? durationSeconds,
});

class ImportSpotifyPlaylistPage extends StatefulWidget {
  const ImportSpotifyPlaylistPage({super.key});

  @override
  State<ImportSpotifyPlaylistPage> createState() =>
      _ImportSpotifyPlaylistPageState();
}

class _ImportSpotifyPlaylistPageState extends State<ImportSpotifyPlaylistPage> {
  // Shared across page instances so navigating away and reopening the page
  // can't spawn a second import running concurrently with the first.
  static bool _importRunning = false;

  // Limit concurrency and leave a short pause between batches.
  static const _batchSize = 12;
  static const _batchPause = Duration(milliseconds: 150);

  final _csvController = TextEditingController();
  final _playlistNameController = TextEditingController();
  bool _isImporting = false;
  String? _fileName;
  int _processedCount = 0;
  int _totalCount = 0;

  @override
  void dispose() {
    _csvController.dispose();
    _playlistNameController.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result.isEmpty || !mounted) return;

    final file = result.single;
    final path = file.path;
    if (path == null) return;
    _csvController.text = await File(path).readAsString();
    if (!mounted) return;
    setState(() => _fileName = file.name);
  }

  Future<void> _importPlaylist() async {
    if (_isImporting) return;
    if (_importRunning) {
      showToast(context, context.l10n!.spotifyPlaylistAlreadyImporting);
      return;
    }
    final playlistName = _playlistNameController.text.trim();
    if (playlistName.isEmpty) {
      showToast(context, context.l10n!.enterPlaylistName);
      return;
    }
    final records = _parseCsv(_csvController.text);
    if (records.length < 2) {
      showToast(context, context.l10n!.spotifyPlaylistEmpty);
      return;
    }

    final headers = records.first
        .map((header) => header.replaceFirst('\ufeff', '').trim().toLowerCase())
        .toList();
    bool isNameColumn(String header) =>
        !header.contains('id') &&
        !header.contains('uri') &&
        !header.contains('url') &&
        !header.contains('genre');
    final songIndex = headers.indexWhere(
      (header) =>
          (header.contains('song') || header.contains('track')) &&
          isNameColumn(header),
    );
    final artistIndex = headers.indexWhere(
      (header) => header.contains('artist') && isNameColumn(header),
    );
    final durationIndex = headers.indexWhere(
      (header) =>
          header.contains('duration') ||
          header == 'time' ||
          header == 'length',
    );
    if (songIndex == -1 || artistIndex == -1) {
      showToast(context, context.l10n!.spotifyPlaylistInvalid);
      return;
    }

    int? parseRowDuration(String? value) {
      if (value == null) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final numVal = double.tryParse(trimmed);
      if (numVal != null && numVal.isFinite && numVal > 0) {
        // Spotify CSV from Chosic/Exportify uses milliseconds for Duration (ms) e.g. 234000
        if (numVal > 1000) {
          return (numVal / 1000).round();
        }
        return numVal.round();
      }
      return readMediaDuration(trimmed)?.inSeconds;
    }

    final songs = records.skip(1).where((row) {
      return row.length > songIndex &&
          row.length > artistIndex &&
          row[songIndex].trim().isNotEmpty;
    }).toList();
    if (songs.isEmpty) {
      showToast(context, context.l10n!.spotifyPlaylistEmpty);
      return;
    }

    final rows = songs.indexed
        .map(
          (entry) => (
            index: entry.$1,
            title: entry.$2[songIndex].trim(),
            artist: entry.$2[artistIndex].trim(),
            durationSeconds: durationIndex != -1 && entry.$2.length > durationIndex
                ? parseRowDuration(entry.$2[durationIndex])
                : null,
          ),
        )
        .toList();

    _importRunning = true;
    setState(() {
      _isImporting = true;
      _processedCount = 0;
      _totalCount = rows.length;
    });

    // Key results by their CSV position so retry results remain ordered.
    final foundByIndex = <int, Map>{};
    List<_ImportRow> missingRows;
    var rateLimited = false;
    try {
      final firstPass = await _searchBatch(
        rows,
        onProgress: (n) {
          if (mounted) setState(() => _processedCount += n);
        },
      );
      foundByIndex.addAll(firstPass.found);
      missingRows = firstPass.missing;
      rateLimited = firstPass.rateLimited;

      // Retry misses once, unless the service is actively rate-limiting us.
      if (!rateLimited && missingRows.isNotEmpty) {
        // Include the retry work in the progress total.
        if (mounted) setState(() => _totalCount += missingRows.length);
        final retryPass = await _searchBatch(
          missingRows,
          onProgress: (n) {
            if (mounted) setState(() => _processedCount += n);
          },
        );
        foundByIndex.addAll(retryPass.found);
        missingRows = retryPass.missing;
        rateLimited = retryPass.rateLimited;
      }
    } finally {
      _importRunning = false;
    }

    final foundSongs = [
      for (final row in rows)
        if (foundByIndex[row.index] case final song?) song,
    ];

    if (!mounted) return;
    final (_, playlistId) = createCustomPlaylist(playlistName, null, context);
    addSongsInCustomPlaylist(context, playlistId, foundSongs);
    setState(() => _isImporting = false);

    if (missingRows.isNotEmpty) {
      final missingText = missingRows
          .map((row) => '${row.title} - ${row.artist}')
          .join('\n');
      await Clipboard.setData(ClipboardData(text: missingText));
    }

    if (mounted) {
      await _showImportResultDialog(
        context: context,
        playlistName: playlistName,
        playlistId: playlistId,
        foundCount: foundSongs.length,
        totalCount: rows.length,
        missingRows: missingRows,
        rateLimited: rateLimited,
      );
    }
  }

  Future<void> _showImportResultDialog({
    required BuildContext context,
    required String playlistName,
    required String playlistId,
    required int foundCount,
    required int totalCount,
    required List<_ImportRow> missingRows,
    required bool rateLimited,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFullSuccess = missingRows.isEmpty && !rateLimited && foundCount > 0;
    final hasPartialSuccess = foundCount > 0 && missingRows.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isFullSuccess
                  ? colorScheme.primaryContainer
                  : hasPartialSuccess
                      ? colorScheme.secondaryContainer
                      : colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFullSuccess
                  ? FluentIcons.checkmark_24_filled
                  : hasPartialSuccess
                      ? FluentIcons.info_24_filled
                      : FluentIcons.warning_24_filled,
              color: isFullSuccess
                  ? colorScheme.onPrimaryContainer
                  : hasPartialSuccess
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onErrorContainer,
              size: 28,
            ),
          ),
          title: Text(
            isFullSuccess
                ? 'Playlist Imported!'
                : hasPartialSuccess
                    ? 'Import Completed with Notes'
                    : 'Import Failed',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.music_note_2_20_filled,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'Saved to your library',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$foundCount',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Imported',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$totalCount',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'In CSV',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (missingRows.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${missingRows.length}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Missing',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (missingRows.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Missing tracks (${missingRows.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          final missingText = missingRows
                              .map((r) => '${r.title} - ${r.artist}')
                              .join('\n');
                          Clipboard.setData(ClipboardData(text: missingText));
                          showToast(
                            context,
                            'Copied missing tracks to clipboard',
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                FluentIcons.copy_16_regular,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Copy',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: missingRows.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 8,
                        thickness: 0.5,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (context, idx) {
                        final r = missingRows[idx];
                        return Text(
                          '${r.title} • ${r.artist}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (rateLimited) ...[
                  const SizedBox(height: 10),
                  Text(
                    'YouTube search was temporarily rate-limited during the import.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (foundCount > 0)
              FilledButton.icon(
                icon: const Icon(
                  FluentIcons.play_circle_20_regular,
                  size: 18,
                ),
                label: const Text('Open Playlist'),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  context.push('/home/playlist/$playlistId');
                },
              ),
          ],
        );
      },
    );
  }

  /// Resolves [rows] in batches and stops when rate limiting is detected.
  /// Results are keyed by the rows' original positions for retry merging.
  Future<({Map<int, Map> found, List<_ImportRow> missing, bool rateLimited})>
  _searchBatch(
    List<_ImportRow> rows, {
    required void Function(int processedCount) onProgress,
  }) async {
    final found = <int, Map>{};
    final missing = <_ImportRow>[];
    for (var i = 0; i < rows.length; i += _batchSize) {
      final batch = rows.skip(i).take(_batchSize).toList();
      final batchResults = await Future.wait(
        batch.map((row) async {
          final (match, wasRateLimited) = await _findSongWithRetry(
            '${row.title} ${row.artist}',
            expectedArtist: row.artist,
            expectedTitle: row.title,
          );
          if (match != null && row.durationSeconds != null) {
            final ytDuration = match['duration'];
            if (ytDuration == null || ytDuration == 0) {
              match['duration'] = row.durationSeconds;
            } else if (ytDuration is num &&
                row.durationSeconds! > 0 &&
                ytDuration > row.durationSeconds! * 1.5) {
              // Prefer exact Spotify duration over doubled or bloated YouTube video duration.
              match['duration'] = row.durationSeconds;
            }
          }
          return (row, match, wasRateLimited);
        }),
      );
      var batchRateLimited = false;
      for (final (row, match, wasRateLimited) in batchResults) {
        if (wasRateLimited) batchRateLimited = true;
        if (match == null) {
          missing.add(row);
        } else {
          found[row.index] = match;
        }
      }
      onProgress(batchResults.length);
      if (batchRateLimited) {
        missing.addAll(rows.skip(i + _batchSize));
        return (found: found, missing: missing, rateLimited: true);
      }
      await Future.delayed(_batchPause);
    }
    return (found: found, missing: missing, rateLimited: false);
  }

  /// Returns the best match for [query], or `null` if none was found.
  /// The second value is `true` when YouTube is actively rate-limiting this
  /// device, so the caller can stop the whole import instead of retrying
  /// every remaining song for minutes on end.
  Future<(Map<String, dynamic>?, bool)> _findSongWithRetry(
    String query, {
    String? expectedArtist,
    String? expectedTitle,
  }) async {
    const maxAttempts = 2;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final video = await ytMusicClient.music.searchSong(
          query,
          expectedArtist: expectedArtist,
          expectedTitle: expectedTitle,
        );
        if (video == null) return (null, false);
        return (Map<String, dynamic>.from(returnSongLayout(0, video)), false);
      } on RequestLimitExceededException {
        // A single short retry for a transient hiccup; a second hit means
        // it's a genuine, sustained block.
        if (attempt == maxAttempts - 1) return (null, true);
        await Future.delayed(const Duration(seconds: 2));
      } catch (e, stackTrace) {
        if (attempt == maxAttempts - 1) {
          logger.log(
            'Error searching Spotify import match for "$query"',
            error: e,
            stackTrace: stackTrace,
          );
          return (null, false);
        }
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    return (null, false);
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;

    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (character == '"') {
        if (quoted && index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((character == '\n' || character == '\r') && !quoted) {
        if (character == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        field = StringBuffer();
        if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(character);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n!.importSpotifyPlaylistTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n!.importSpotifyPlaylistInstructions),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => launchURL(
                Uri.parse('https://www.chosic.com/spotify-playlist-exporter/'),
              ),
              icon: const Icon(FluentIcons.open_24_regular),
              label: Text(context.l10n!.openChosicExporter),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _chooseFile,
              icon: const Icon(FluentIcons.document_add_24_regular),
              label: Text(_fileName ?? context.l10n!.chooseCsvFile),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _playlistNameController,
              enabled: !_isImporting,
              decoration: InputDecoration(
                labelText: '${context.l10n!.playlistName} *',
                hintText: context.l10n!.spotifyPlaylistNameHint,
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _csvController,
              enabled: !_isImporting,
              minLines: 10,
              maxLines: 18,
              decoration: InputDecoration(
                labelText: context.l10n!.pasteCsv,
                hintText: context.l10n!.spotifyCsvHint,
                alignLabelWithHint: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isImporting ? null : _importPlaylist,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.arrow_upload_24_regular),
              label: Text(
                _isImporting
                    ? context.l10n!.spotifyPlaylistImporting
                    : context.l10n!.importPlaylist,
              ),
            ),
            if (_isImporting && _totalCount > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _processedCount / _totalCount,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n!.spotifyPlaylistProgress(
                  _processedCount,
                  _totalCount,
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: MiniPlayer.playerHeight + 24),
          ],
        ),
      ),
    );
  }
}
