import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../data/thc_repository.dart';

/// Bottom sheet listing active staff (drivers, delivery partners); pops with the pick.
class StaffPickerSheet extends ConsumerStatefulWidget {
  const StaffPickerSheet({super.key, this.hint = 'Search driver by name or mobile'});

  final String hint;

  @override
  ConsumerState<StaffPickerSheet> createState() => _StaffPickerSheetState();
}

class _StaffPickerSheetState extends ConsumerState<StaffPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(staffUsersProvider);
    final branchId = ref.watch(sessionProvider)?.operatingBranchId;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: switch (users) {
                AsyncData(:final value) => () {
                  final list =
                      value
                          .where(
                            (u) => _q.isEmpty || u.name.toLowerCase().contains(_q) || (u.mobile ?? '').contains(_q),
                          )
                          .toList()
                        // This branch's staff first.
                        ..sort((a, b) {
                          final ab = a.branchId == branchId ? 0 : 1;
                          final bb = b.branchId == branchId ? 0 : 1;
                          return ab != bb ? ab - bb : a.name.compareTo(b.name);
                        });
                  if (list.isEmpty) return const EmptyView(message: 'No matching staff.');
                  return ListView(
                    children: [
                      for (final u in list)
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(u.name),
                          subtitle: Text([u.mobile, u.designation].nonNulls.join(' · ')),
                          onTap: () => Navigator.pop(context, u),
                        ),
                    ],
                  );
                }(),
                AsyncError(:final error) =>
                  error is ApiException && error.kind == ApiErrorKind.forbidden
                      ? const EmptyView(
                          icon: Icons.lock_outline,
                          message:
                              'Your role cannot list staff.\nAsk your branch manager, '
                              'or ask an admin for the USER_READ permission.',
                        )
                      : ErrorView(error: error, onRetry: () => ref.invalidate(staffUsersProvider)),
                _ => const LoadingView(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
