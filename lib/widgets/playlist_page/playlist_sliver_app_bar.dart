import 'package:material_ui/material_ui.dart';

class PlaylistSliverAppBar extends StatelessWidget {
  const PlaylistSliverAppBar({
    super.key,
    required this.title,
    required this.artwork,
    this.leading,
  });

  final String title;
  final Widget artwork;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return SliverAppBar(
      leading: leading,
      pinned: true,
      expandedHeight: screenSize.width > screenSize.height ? 380 : 340,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        expandedTitleScale: 1.35,
        titlePadding: const EdgeInsetsDirectional.only(
          start: 64,
          end: 64,
          bottom: 16,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: 0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        background: Padding(
          padding: const EdgeInsets.only(top: 56, bottom: 64),
          child: Center(child: artwork),
        ),
      ),
    );
  }
}
