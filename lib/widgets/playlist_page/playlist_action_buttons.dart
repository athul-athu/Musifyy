import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';

/// Play and shuffle whatever the page is about, shared by the playlist and the
/// artist pages. While [isLoading] the songs are still being read, so both
/// buttons wait instead of playing an incomplete list.
class PlaylistActionButtons extends StatelessWidget {
  const PlaylistActionButtons({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    this.isLoading = false,
  });

  final VoidCallback onPlay;

  final AsyncCallback onShuffle;

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: isLoading
                  ? const _Spinner()
                  : const Icon(FluentIcons.play_24_filled),
              label: Text(context.l10n!.play),
              onPressed: isLoading ? null : onPlay,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.secondaryContainer,
                foregroundColor: colorScheme.onSecondaryContainer,
              ),
              icon: isLoading
                  ? const _Spinner()
                  : const Icon(FluentIcons.arrow_shuffle_24_filled),
              label: Text(context.l10n!.shuffle),
              onPressed: isLoading ? null : onShuffle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Replaces the icon of a button while its songs are being read.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
