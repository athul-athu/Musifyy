import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/widgets/playlist_cube.dart';

class PlaylistHeroArtwork extends StatelessWidget {
  const PlaylistHeroArtwork(
    this.playlist, {
    super.key,
    this.cubeIcon = FluentIcons.text_bullet_list_24_filled,
  });

  final Map playlist;
  final IconData cubeIcon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final preferredSize = screenSize.width > screenSize.height
            ? 240.0
            : screenSize.width / (commonPlaylistArtworkDivision - 0.1);
        final size = preferredSize
            .clamp(0.0, min(constraints.maxWidth, constraints.maxHeight))
            .toDouble();
        final artwork = PlaylistCube(
          playlist,
          size: size,
          cubeIcon: cubeIcon,
          showTypeLabel: false,
        );

        return ClipPath(
          clipper: const ShapeBorderClipper(
            shape: StarBorder(
              points: 8,
              pointRounding: 0.8,
              valleyRounding: 0.2,
              innerRadiusRatio: 0.6,
            ),
          ),
          child: artwork,
        );
      },
    );
  }
}
