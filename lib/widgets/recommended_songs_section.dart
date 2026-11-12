import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/main.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/widgets/section_header.dart';
import 'package:musify/widgets/song_bar.dart';

/// Shared titled list of recommended songs with an optional "play all" button.
class RecommendedSongsSection extends StatelessWidget {
  const RecommendedSongsSection({
    super.key,
    required this.title,
    required this.songs,
    required this.listKeyPrefix,
    this.showPlayButton = true,
    this.onAddSong,
  });

  final String title;
  final List<dynamic> songs;

  /// Scope passed to [listItemKey] so each usage keeps stable, distinct keys.
  final String listKeyPrefix;
  final bool showPlayButton;

  /// When set, each row shows an add button instead of the overflow menu.
  final void Function(Map song)? onAddSong;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionHeader(
          title: title,
          icon: FluentIcons.sparkle_24_filled,
          actionButton: showPlayButton
              ? IconButton(
                  onPressed: () async {
                    await audioHandler.playPlaylistSong(
                      playlist: {'title': title, 'list': songs},
                      songIndex: 0,
                      shuffle: false,
                    );
                  },
                  icon: Icon(
                    FluentIcons.play_circle_24_filled,
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                )
              : null,
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          itemCount: songs.length,
          padding: commonListViewBottomPadding,
          itemBuilder: (context, index) {
            final song = songs[index];
            final borderRadius = getItemBorderRadius(index, songs.length);
            return RepaintBoundary(
              key: listItemKey(listKeyPrefix, index, song),
              child: SongBar(
                song,
                true,
                barPadding: const EdgeInsetsDirectional.only(
                  top: 10,
                  bottom: 10,
                  start: 12,
                ),
                borderRadius: borderRadius,
                onAdd: onAddSong != null && song is Map
                    ? () => onAddSong!(song)
                    : null,
              ),
            );
          },
        ),
      ],
    );
  }
}
