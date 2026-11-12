import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/playlist_dialogs.dart';

/// Adds every song of a resolved playlist to one of the user's playlists.
///
/// The artist landing page only has its ranked songs on screen, so resolving
/// on demand is what makes this action share the complete "All songs" catalog.
class PlaylistAddToPlaylistButton extends StatefulWidget {
  const PlaylistAddToPlaylistButton({super.key, required this.resolvePlaylist});

  final Future<Map?> Function() resolvePlaylist;

  @override
  State<PlaylistAddToPlaylistButton> createState() =>
      _PlaylistAddToPlaylistButtonState();
}

class _PlaylistAddToPlaylistButtonState
    extends State<PlaylistAddToPlaylistButton> {
  bool _isResolving = false;

  @override
  Widget build(BuildContext context) {
    if (_isResolving) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }

    return IconButton.filledTonal(
      icon: const Icon(FluentIcons.album_add_24_regular),
      iconSize: 24,
      onPressed: _resolveAndAdd,
      tooltip: context.l10n!.addToPlaylist,
    );
  }

  Future<void> _resolveAndAdd() async {
    if (_isResolving) return;
    setState(() => _isResolving = true);

    Map? playlist;
    try {
      playlist = await widget.resolvePlaylist();
    } catch (_) {
      if (mounted) showToast(context, context.l10n!.error);
      return;
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
    if (!mounted) return;

    if (playlist == null || playlist['list'] is! List) {
      showToast(context, context.l10n!.error);
      return;
    }

    final songs = playlist['list'] as List;
    if (songs.isEmpty) {
      showToast(context, context.l10n!.noSongsInPlaylist);
      return;
    }

    showAddToPlaylistDialog(context, songs: songs);
  }
}
