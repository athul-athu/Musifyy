import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

class BottomSheetBar extends StatelessWidget {
  const BottomSheetBar(
    this.title,
    this.onTap,
    this.isSelected, {
    this.icon,
    super.key,
  });
  final String title;
  final VoidCallback onTap;
  final bool isSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = isSelected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerHigh;
    final fgColor = isSelected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.onSecondaryContainer.withValues(
                              alpha: 0.12,
                            )
                          : colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.08,
                            ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: fgColor),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 15,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    FluentIcons.checkmark_circle_24_regular,
                    color: colorScheme.onSecondaryContainer,
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
