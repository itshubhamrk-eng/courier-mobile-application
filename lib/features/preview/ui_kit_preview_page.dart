import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/movement_timeline.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/submit_button.dart';

/// Phase 0 review screen for the theme and shared widgets. Sample values only;
/// removed when the real screens land in Phase 1.
class UiKitPreviewPage extends StatelessWidget {
  const UiKitPreviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('UI kit preview')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Section('Dashboard cards'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: const [
              StatCard(label: "Today's bookings", value: 0, icon: Icons.inventory_2_outlined),
              StatCard(
                label: 'Pending loading',
                value: 0,
                icon: Icons.local_shipping_outlined,
                color: AppColors.warning,
              ),
              StatCard(label: 'Delivered', value: null, icon: Icons.task_alt, color: AppColors.success),
            ],
          ),
          const _Section('Status badges'),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge('BOOKED'),
              StatusBadge('MANIFEST_CREATED'),
              StatusBadge('DISPATCHED'),
              StatusBadge('OUT_FOR_DELIVERY'),
              StatusBadge('DELIVERED'),
              StatusBadge('NOT_DELIVERED'),
              StatusBadge('ON_HOLD'),
              StatusBadge('RTO'),
            ],
          ),
          const _Section('Search'),
          TextField(
            decoration: InputDecoration(
              hintText: 'AWB number',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(onPressed: () {}, icon: const Icon(Icons.qr_code_scanner)),
            ),
          ),
          const _Section('Timeline'),
          MovementTimeline(
            entries: [
              TimelineEntry(status: 'DISPATCHED', at: now, location: 'Sample branch', remarks: 'Sample remark'),
              TimelineEntry(status: 'BOOKED', at: now.subtract(const Duration(hours: 3)), location: 'Sample branch'),
            ],
          ),
          const _Section('Submit'),
          SubmitButton(
            label: 'Confirm booking',
            icon: Icons.check,
            onPressed: () => Future<void>.delayed(const Duration(seconds: 2)),
          ),
          const _Section('States'),
          const SizedBox(height: 160, child: EmptyView(message: 'No loading sheets yet.')),
          SizedBox(
            height: 200,
            child: ErrorView(
              error: const ApiException(ApiErrorKind.network, 'No connection. Check your internet and try again.'),
              onRetry: () {},
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
    ),
  );
}
