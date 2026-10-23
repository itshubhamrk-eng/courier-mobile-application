import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Label and colour for a courier-service `ShipmentStatus` (or exception / POD
/// entry status). Unknown values are shown as sent, never guessed.
({String label, Color color}) statusStyle(String status) => switch (status) {
  'BOOKED' => (label: 'Booked', color: AppColors.info),
  'READY_FOR_MANIFEST' => (label: 'Ready for Loading', color: AppColors.info),
  'MANIFEST_CREATED' => (label: 'Loading Sheet Created', color: AppColors.primary),
  'DISPATCHED' => (label: 'Dispatched', color: AppColors.primary),
  'IN_SCAN' => (label: 'Received', color: AppColors.primary),
  'OUT_FOR_DELIVERY' => (label: 'Out for Delivery', color: AppColors.warning),
  'DELIVERED' => (label: 'Delivered', color: AppColors.success),
  'RETURNED' || 'RTO' => (label: 'Returned (RTO)', color: AppColors.danger),
  'CANCELLED' => (label: 'Cancelled', color: AppColors.neutral),
  'NOT_DELIVERED' => (label: 'Delivery Failed', color: AppColors.danger),
  'ON_HOLD' => (label: 'On Hold', color: AppColors.warning),
  'MISROUTED' || 'WRONG_DESTINATION' => (label: 'Misrouted', color: AppColors.danger),
  'CREATED' => (label: 'Created', color: AppColors.info),
  'COMPLETED' => (label: 'Completed', color: AppColors.success),
  _ => (label: status, color: AppColors.neutral),
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: style.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        style.label,
        style: TextStyle(color: style.color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
