import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';

class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    super.key,
    this.confirmationMessage,
    required this.submitMessage,
    required this.onCancel,
    required this.onSubmit,
    this.isDangerous = false,
  });
  final String? confirmationMessage;
  final String submitMessage;
  final VoidCallback? onCancel;
  final VoidCallback? onSubmit;
  final bool isDangerous;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        isDangerous
            ? FluentIcons.warning_24_regular
            : FluentIcons.question_circle_24_regular,
        color: isDangerous ? colorScheme.error : colorScheme.primary,
        size: 32,
      ),
      title: Text(
        context.l10n!.confirmation,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: confirmationMessage != null
          ? Text(
              confirmationMessage!,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            )
          : null,
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(context.l10n!.cancel),
        ),
        FilledButton(
          onPressed: onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: isDangerous
                ? colorScheme.error
                : colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(submitMessage),
        ),
      ],
    );
  }
}
