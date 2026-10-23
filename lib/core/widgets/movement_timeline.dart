import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'status_badge.dart';

/// One recorded movement event. Built only from server history; never invented.
class TimelineEntry {
  const TimelineEntry({required this.status, required this.at, this.location, this.remarks, this.by});

  final String status;
  final DateTime at;
  final String? location;
  final String? remarks;
  final String? by;
}

class MovementTimeline extends StatelessWidget {
  const MovementTimeline({super.key, required this.entries});

  /// Newest first.
  final List<TimelineEntry> entries;

  static final _format = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) _Row(entry: entries[i], first: i == 0, last: i == entries.length - 1),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.first, required this.last});

  final TimelineEntry entry;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = statusStyle(entry.status).color;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(width: 2, height: 6, color: first ? Colors.transparent : AppColors.border),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: first ? color : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2.5),
                  ),
                ),
                Expanded(child: Container(width: 2, color: last ? Colors.transparent : AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(entry.status),
                  const SizedBox(height: 4),
                  Text(
                    MovementTimeline._format.format(entry.at.toLocal()),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (entry.location != null)
                    Text(entry.location!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (entry.remarks != null && entry.remarks!.isNotEmpty) Text(entry.remarks!),
                  if (entry.by != null)
                    Text('by ${entry.by}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
