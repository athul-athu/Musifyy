import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/confirmation_dialog.dart';

void showRemoveOfflinePlaylistDialog(BuildContext context, String playlistId) {
  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return ConfirmationDialog(
        confirmationMessage: context.l10n!.removeOfflinePlaylistConfirm,
        submitMessage: context.l10n!.remove,
        isDangerous: true,
        onCancel: () => Navigator.pop(context),
        onSubmit: () {
          offlinePlaylistService.removeOfflinePlaylist(playlistId);
          Navigator.pop(context);
          showToast(context, context.l10n!.playlistRemovedFromOffline);
        },
      );
    },
  );
}
