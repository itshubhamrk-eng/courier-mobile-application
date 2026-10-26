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
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 64),
            const SizedBox(height: 12),
            const Text(
              'Shipment booked',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('AWB number', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SelectableText(
                          value.shipment.trackingNumber,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1),
                        ),
                        IconButton(
                          tooltip: 'Copy AWB',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: value.shipment.trackingNumber));
                            if (context.mounted) showSuccess(context, 'AWB copied');
                          },
                        ),
                      ],
                    ),
                    Text('Shipment ${value.shipment.shipmentNumber}'),
                    if (value.charges?.netAmount != null) ...[
                      const Divider(height: 28),
                      const Text('Net amount', style: TextStyle(color: AppColors.textSecondary)),
                      Text(
                        Fmt.money(value.charges!.netAmount),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.pushReplacement('/shipments/$shipmentId'),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View shipment'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => context.pushReplacement('/bookings/new'),
              icon: const Icon(Icons.add),
              label: const Text('Book another'),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => context.go('/home'), child: const Text('Done')),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => openDocument(
                context,
                title: 'Labels ${value.shipment.trackingNumber}',
                fileName: 'label-${value.shipment.trackingNumber}.pdf',
                build: () => ref.read(documentServiceProvider).label(shipmentId),
              ),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print labels'),
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
