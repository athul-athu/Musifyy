import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/widgets/mini_player.dart';

void showToast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(seconds: 3),
  IconData? icon,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final isMiniPlayerVisible = audioHandler.mediaItem.value != null;
  final bottomMargin =
      12.0 + (isMiniPlayerVisible ? MiniPlayer.playerHeight : 0.0);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      margin: EdgeInsets.fromLTRB(16, 12, 16, bottomMargin),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      content: Row(
        children: [
          Icon(
            icon ?? FluentIcons.checkmark_circle_20_regular,
            color: colorScheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
      duration: duration,
    ),
  );
}

void showToastWithButton(
  BuildContext context,
  String text,
  String buttonName,
  VoidCallback onPressedToast, {
  Duration duration = const Duration(seconds: 3),
  IconData? icon,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final isMiniPlayerVisible = audioHandler.mediaItem.value != null;
  final bottomMargin =
      12.0 + (isMiniPlayerVisible ? MiniPlayer.playerHeight : 0.0);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      margin: EdgeInsets.fromLTRB(16, 12, 16, bottomMargin),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      content: Row(
        children: [
          Icon(
            icon ?? FluentIcons.info_20_regular,
            color: colorScheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
      action: SnackBarAction(
        label: buttonName,
        onPressed: () => onPressedToast(),
      ),
      persist: false,
      duration: duration,
    ),
  );
}
