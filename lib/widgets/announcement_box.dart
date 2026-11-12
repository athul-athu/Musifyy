import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/utilities/url_launcher.dart';

class AnnouncementBox extends StatelessWidget {
  const AnnouncementBox({
    super.key,
    required this.message,
    required this.url,
    this.onDismiss,
    this.icon = FluentIcons.megaphone_24_regular,
  });
  final String message;
  final String url;
  final VoidCallback? onDismiss;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => launchURL(Uri.parse(url)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: colorScheme.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            context.l10n!.tapToView,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            FluentIcons.arrow_right_16_regular,
                            size: 12,
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: Icon(
                      FluentIcons.dismiss_circle_24_regular,
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                    onPressed: onDismiss,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
