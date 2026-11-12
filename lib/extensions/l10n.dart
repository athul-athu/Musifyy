import 'package:flutter/widgets.dart';
import 'package:musify/localization/app_localizations.dart';

extension ContextX on BuildContext {
  AppLocalizations? get l10n => AppLocalizations.of(this);
}
