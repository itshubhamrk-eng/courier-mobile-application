import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dashboard count card, tinted in its operation's colour. [value] null shows
/// a dash (figure could not be loaded).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
    this.onTap,
  });

  final String label;
  final int? value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.alphaBlend(color.withValues(alpha: 0.09), AppColors.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(height: 8),
              Text(
                value?.toString() ?? '–',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color.lerp(color, Colors.black, 0.25),
                ),
              ),
              // Flexible: a long label ellipsizes instead of overflowing a fixed-height grid cell.
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.25, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
