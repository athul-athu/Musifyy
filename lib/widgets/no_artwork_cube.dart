import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

class NullArtworkWidget extends StatelessWidget {
  const NullArtworkWidget({
    super.key,
    this.icon = FluentIcons.music_note_1_24_regular,
    this.size = 220,
    this.iconSize,
    this.title,
    this.borderRadius = 20,
  });

  final IconData icon;
  final double? iconSize;
  final double size;
  final String? title;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final badgeSize = size * 0.4;
    final calculatedIconSize = iconSize ?? (badgeSize * 0.5);

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: badgeSize,
                height: badgeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primaryContainer.withValues(alpha: 0.55),
                ),
                child: Icon(
                  icon,
                  size: calculatedIconSize,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              if (title != null) ...[
                SizedBox(height: size * 0.045),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size * 0.08),
                  child: Text(
                    title!,
                    textAlign: TextAlign.center,
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
