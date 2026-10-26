import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rounded tinted square holding an icon: the app's section and row marker.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color = AppColors.primary, this.size = 36});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.3)),
    child: Icon(icon, color: color, size: size * 0.55),
  );
}

/// Section heading used above groups of fields: coloured icon badge plus title.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.icon, this.color = AppColors.primary, this.trailing});

  final String title;
  final IconData? icon;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[IconBadge(icon!, color: color, size: 32), const SizedBox(width: 10)],
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
      ),
      ?trailing,
    ],
  );
}

/// A white card with a [SectionTitle] header.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.children,
    this.title,
    this.icon,
    this.color = AppColors.primary,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final IconData? icon;
  final Color color;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              SectionTitle(title!, icon: icon, color: color, trailing: trailing),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// Label on the left, value on the right. Hidden when there is no value.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false});

  final String label;
  final String? value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final v = value;
    if (v == null || v.isEmpty || v == '–') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600, fontSize: bold ? 16 : 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Origin to destination with a dotted connector.
class RouteStrip extends StatelessWidget {
  const RouteStrip({super.key, required this.from, required this.to, this.fromSub, this.toSub, this.onDark = false});

  final String from;
  final String to;
  final String? fromSub;
  final String? toSub;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : AppColors.textPrimary;
    final sub = onDark ? Colors.white70 : AppColors.textSecondary;
    Widget end(String title, String? subtitle, CrossAxisAlignment align) => Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: align == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sub, fontSize: 12),
            ),
        ],
      ),
    );
    return Row(
      children: [
        end(from, fromSub, CrossAxisAlignment.start),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(Icons.trip_origin, size: 14, color: sub),
              for (var i = 0; i < 5; i++)
                Container(width: 4, height: 2, margin: const EdgeInsets.symmetric(horizontal: 2), color: sub),
              Icon(Icons.location_on, size: 18, color: onDark ? Colors.white : AppColors.danger),
            ],
          ),
        ),
        end(to, toSub, CrossAxisAlignment.end),
      ],
    );
  }
}

/// Small figure with a caption, laid out in a row of equal tiles.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.value, required this.label, this.icon, this.color = AppColors.primary});

  final String value;
  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(height: 6)],
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

/// Gradient header card used at the top of detail screens.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.colors = const [AppColors.primary, AppColors.indigo]});

  final Widget child;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: child,
  );
}

/// The app's signature gradient: blue through indigo to violet.
const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.primary, AppColors.indigo, AppColors.purple],
);

/// Paints [brandGradient] behind an AppBar (`flexibleSpace`).
class AppBarGradient extends StatelessWidget {
  const AppBarGradient({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand(
    child: DecoratedBox(decoration: BoxDecoration(gradient: brandGradient)),
  );
}

/// List card with a coloured left edge and an icon badge: used for sheets, runs
/// and other records so each list has its own colour.
class AccentCard extends StatelessWidget {
  const AccentCard({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBadge(icon, color: color, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              ),
                              ?trailing,
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...children,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Decoration for the "scan or type AWB" box: tinted, with a gradient camera button.
InputDecoration scanDecoration(String hint, {required VoidCallback? onScan, bool busy = false}) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: AppColors.primaryLight,
  prefixIcon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.35), width: 1.2),
  ),
  suffixIcon: Padding(
    padding: const EdgeInsets.all(6),
    child: busy
        ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2))
        : DecoratedBox(
            decoration: BoxDecoration(gradient: brandGradient, borderRadius: BorderRadius.circular(10)),
            child: IconButton(
              tooltip: 'Scan',
              icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              onPressed: onScan,
            ),
          ),
  ),
);

/// Selectable record row (loading, receiving, DRS): tints and shows a check when picked.
class PickTile extends StatelessWidget {
  const PickTile({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.title,
    this.badge,
    this.lines = const [],
    this.color = AppColors.success,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;
  final String title;
  final Widget? badge;
  final List<Widget> lines;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: selected ? color.withValues(alpha: 0.08) : AppColors.surface,
      elevation: selected ? 0 : 2,
      shadowColor: AppColors.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? color : Colors.transparent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!selected),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? color : Colors.transparent,
                  border: Border.all(color: selected ? color : AppColors.border, width: 2),
                ),
                child: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        ?badge,
                      ],
                    ),
                    if (lines.isNotEmpty) const SizedBox(height: 4),
                    ...lines,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Coloured figure for sticky totals bars.
class TotalChip extends StatelessWidget {
  const TotalChip({super.key, required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    ),
  );
}
