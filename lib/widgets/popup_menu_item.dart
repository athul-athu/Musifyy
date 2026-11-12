import 'package:material_ui/material_ui.dart';

/// Creates a PopupMenuItem with consistent icon + label styling
PopupMenuItem<T> buildPopupMenuItem<T>({
  required T value,
  required IconData icon,
  required String label,
  required ColorScheme colorScheme,
  Color? iconColor,
  TextStyle? labelStyle,
  double iconSize = 24,
  double spacing = 8,
}) {
  return PopupMenuItem<T>(
    value: value,
    child: Row(
      children: [
        Icon(icon, color: iconColor ?? colorScheme.primary, size: iconSize),
        SizedBox(width: spacing),
        Text(
          label,
          style: labelStyle ?? TextStyle(color: colorScheme.onSurface),
        ),
      ],
    ),
  );
}
