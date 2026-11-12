import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

class OverflowMenuButton<T> extends StatelessWidget {
  const OverflowMenuButton({
    super.key,
    required this.onSelected,
    required this.itemBuilder,
    this.icon,
    this.borderRadius,
    this.iconSize = 24,
    this.color,
  });

  final void Function(T value) onSelected;
  final List<PopupMenuEntry<T>> Function(BuildContext context) itemBuilder;

  final IconData? icon;
  final double iconSize;
  final Color? color;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<T>(
      borderRadius: borderRadius ?? BorderRadius.circular(12),
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      icon: Icon(
        icon ?? FluentIcons.more_vertical_24_regular,
        size: iconSize,
        color: color ?? colorScheme.onSurfaceVariant,
      ),
    );
  }
}
