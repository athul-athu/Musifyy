import 'package:material_ui/material_ui.dart';

BuildContext? _currentBottomSheetContext;

Future<T?> showCustomBottomSheet<T>(
  BuildContext context,
  Widget content,
) {
  final size = MediaQuery.sizeOf(context);
  final colorScheme = Theme.of(context).colorScheme;

  closeCurrentBottomSheet();

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    elevation: 0,
    builder: (sheetContext) {
      _currentBottomSheetContext = sheetContext;
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: GestureDetector(
                  onTap: () => Navigator.of(sheetContext).pop(),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
    },
  ).whenComplete(() {
    _currentBottomSheetContext = null;
  });
}

void closeCurrentBottomSheet() {
  if (_currentBottomSheetContext != null &&
      _currentBottomSheetContext!.mounted) {
    try {
      Navigator.of(_currentBottomSheetContext!).pop();
    } catch (_) {}
  }
  _currentBottomSheetContext = null;
}
