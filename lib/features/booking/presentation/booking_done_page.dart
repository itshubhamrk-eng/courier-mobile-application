import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../shipments/data/shipment_repository.dart';
import '../../documents/document_page.dart';
import '../../documents/document_service.dart';
import '../../../core/widgets/ui.dart';

/// After booking: the server's AWB and its final charges.
class BookingDonePage extends ConsumerWidget {
  const BookingDonePage({super.key, required this.shipmentId});

  final String shipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (id: shipmentId, withCharges: true);
    final view = ref.watch(shipmentViewByIdProvider(key));

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const AppBarGradient(),
        title: const Text('Booked'),
        automaticallyImplyLeading: false,
      ),
      body: switch (view) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            HeroCard(
              colors: const [AppColors.green, AppColors.teal],
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: AppColors.green, size: 44),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Shipment booked',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text('AWB NUMBER', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SelectableText(
                        value.shipment.trackingNumber,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy AWB',
                        icon: const Icon(Icons.copy, color: Colors.white),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: value.shipment.trackingNumber));
                          if (context.mounted) showSuccess(context, 'AWB copied');
                        },
                      ),
                    ],
                  ),
                  Text('Shipment ${value.shipment.shipmentNumber}', style: const TextStyle(color: Colors.white70)),
                  if (value.charges?.netAmount != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                      child: Text(
                        'Net amount  ${Fmt.money(value.charges!.netAmount)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _Action(
                  'View shipment',
                  Icons.receipt_long_outlined,
                  AppColors.indigo,
                  () => context.pushReplacement('/shipments/$shipmentId'),
                ),
                _Action(
                  'Print labels',
                  Icons.print_outlined,
                  AppColors.purple,
                  () => openDocument(
                    context,
                    title: 'Labels ${value.shipment.trackingNumber}',
                    fileName: 'label-${value.shipment.trackingNumber}.pdf',
                    build: () => ref.read(documentServiceProvider).label(shipmentId),
                  ),
                ),
                _Action(
                  'Book another',
                  Icons.add_box_outlined,
                  AppColors.teal,
                  () => context.pushReplacement('/bookings/new'),
                ),
                _Action('Done', Icons.home_outlined, AppColors.orange, () => context.go('/home')),
              ],
            ),
          ],
        ),
        AsyncError(:final error) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('The shipment was booked, but its details could not be loaded.', textAlign: TextAlign.center),
            ),
            ErrorView(error: error, onRetry: () => ref.invalidate(shipmentViewByIdProvider(key))),
            TextButton(onPressed: () => context.go('/bookings'), child: const Text('Open Bookings')),
          ],
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.color, this.onTap);

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    ),
  );
}
