import 'package:material_ui/material_ui.dart';

PersistentBottomSheetController? _currentBottomSheetController;

PersistentBottomSheetController? showCustomBottomSheet(
  BuildContext context,
  Widget content,
) {
  final size = MediaQuery.sizeOf(context);
  final colorScheme = Theme.of(context).colorScheme;

  final controller = showBottomSheet(
    enableDrag: true,
    context: context,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: size.width * 0.92,
              maxHeight: size.height * 0.65,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: content,
            ),
          ),
        ],
      ),
    ),
  );

  _currentBottomSheetController = controller;
  controller.closed.whenComplete(() {
    if (_currentBottomSheetController == controller) {
      _currentBottomSheetController = null;
    }
  });

  return controller;
}

void closeCurrentBottomSheet() {
  try {
    _currentBottomSheetController?.close();
  } catch (_) {}
  _currentBottomSheetController = null;
}
