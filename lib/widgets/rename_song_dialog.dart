import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/widgets/mini_player.dart';

class RenameSongDialog extends StatefulWidget {
  const RenameSongDialog({
    super.key,
    required this.currentTitle,
    required this.currentArtist,
    required this.onRename,
  });

  final String currentTitle;
  final String currentArtist;
  final Function(String newTitle, String newArtist) onRename;

  @override
  State<RenameSongDialog> createState() => _RenameSongDialogState();
}

class _RenameSongDialogState extends State<RenameSongDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.currentTitle);
    _artistController = TextEditingController(text: widget.currentArtist);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  void _handleRename() {
    final newTitle = _titleController.text.trim();
    final newArtist = _artistController.text.trim();

    if (newTitle.isEmpty || newArtist.isEmpty) {
      final isMiniPlayerVisible = audioHandler.mediaItem.value != null;
      final bottomMargin =
          12.0 + (isMiniPlayerVisible ? MiniPlayer.playerHeight : 0.0);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 12, 16, bottomMargin),
          content: Text(context.l10n!.fieldsNotEmpty),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    widget.onRename(newTitle, newArtist);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        context.l10n!.renameSong,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: context.l10n!.name,
                labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
              style: TextStyle(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _artistController,
              decoration: InputDecoration(
                labelText: context.l10n!.artist,
                labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
              ),
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(context.l10n!.cancel),
        ),
        FilledButton(
          onPressed: _handleRename,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(context.l10n!.confirm),
        ),
      ],
    );
  }
}
