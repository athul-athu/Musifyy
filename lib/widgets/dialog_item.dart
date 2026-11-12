import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';

class DialogItem extends StatelessWidget {
  const DialogItem({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.label,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
    this.iconRightPadding = 12,
    this.iconSize = 22,
    this.iconContainerSize = 44,
    this.fontSize = 15,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String label;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final double iconRightPadding;
  final double iconSize;
  final double iconContainerSize;
  final double fontSize;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: commonBarRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: iconRightPadding,
              vertical: 12,
            ),
            child: Row(
              children: [
                Container(
                  width: iconContainerSize,
                  height: iconContainerSize,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: iconSize),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                ),
                if (showChevron)
                  Icon(
                    FluentIcons.chevron_right_24_regular,
                    color: colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
