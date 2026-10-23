import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../auth/application/auth_controller.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    bool can(String p) => session?.can(p) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          if (session != null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  session.displayName.isEmpty ? '?' : session.displayName[0].toUpperCase(),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(session.displayName),
              subtitle: Text([session.email, ?session.companyName].join(' · ')),
            ),
          const Divider(),
          if (can(Permissions.shipmentRead))
            _Item(icon: Icons.search, label: 'Track Shipment', onTap: () => context.push('/track')),
          if (can(Permissions.manifestDispatch))
            _Item(
              icon: Icons.local_shipping_outlined,
              label: 'THC — Transport Hire Challan',
              onTap: () => context.push('/thc'),
            ),
          if (can(Permissions.deliveryAssign))
            _Item(
              icon: Icons.assignment_outlined,
              label: 'DRS — Delivery Run Sheet',
              onTap: () => context.push('/drs/new'),
            ),
          if (can(Permissions.deliveryUpload))
            _Item(
              icon: Icons.photo_camera_outlined,
              label: 'POD — Proof of Delivery',
              onTap: () => context.push('/pod'),
            ),
          const Divider(),
          _Item(
            icon: Icons.logout,
            label: 'Sign out',
            color: AppColors.danger,
            onTap: () async {
              final ok = await confirmAction(
                context,
                title: 'Sign out?',
                message: 'You will need your password to sign in again.',
                confirmLabel: 'Sign out',
              );
              if (ok) await ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color ?? AppColors.primary),
    title: Text(label, style: TextStyle(color: color)),
    trailing: color == null ? const Icon(Icons.chevron_right) : null,
    onTap: onTap,
  );
}
