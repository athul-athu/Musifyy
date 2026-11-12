import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/section_title.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.actionButton,
  });
  final String title;
  final IconData? icon;
  final Widget? actionButton;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: SectionTitle(
            title,
            Theme.of(context).colorScheme.primary,
            icon: icon,
          ),
        ),
        if (actionButton != null) actionButton!,
      ],
    );
  }
}
