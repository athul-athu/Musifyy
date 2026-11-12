import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/marquee.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, this.primaryColor, {super.key, this.icon});
  final Color primaryColor;
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: MarqueeWidget(
              child: Text(
                title,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize:
                      Theme.of(context).textTheme.titleMedium?.fontSize ?? 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
