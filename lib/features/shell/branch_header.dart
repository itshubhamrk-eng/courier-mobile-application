import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/config/env.dart';
import '../../core/format.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../auth/application/auth_controller.dart';
import '../masters/data/masters.dart';

/// Branch wallet (`GET /api/v1/branch-wallet`: the caller's own branch).
class BranchWallet {
  const BranchWallet({required this.available, this.hold, this.currency});

  final num available;
  final num? hold;
  final String? currency;
}

/// Refreshed by pull-to-refresh on Home and after a booking (prepaid bookings debit it).
final branchWalletProvider = FutureProvider<BranchWallet?>((ref) async {
  final userId = ref.watch(sessionProvider.select((s) => s?.userId));
  if (userId == null) return null;
  return ref
      .watch(apiClientProvider)
      .get(
        '/api/v1/branch-wallet',
        parse: (d) {
          final j = jMap(d);
          final available = jNum(j['availableBalance']);
          return available == null
              ? null
              : BranchWallet(available: available, hold: jNum(j['holdBalance']), currency: jStr(j['currency']));
        },
      );
});

/// Top header on the main screens, like the web app's: menu, company logo and
/// name, branch name, wallet balance.
class BranchHeader extends ConsumerWidget implements PreferredSizeWidget {
  const BranchHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 4);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final branch = (ref.watch(branchNamesProvider).value ?? const {})[session?.operatingBranchId];
    return AppBar(
      toolbarHeight: kToolbarHeight + 4,
      titleSpacing: 0,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      title: Row(
        children: [
          CompanyLogo(name: session?.companyName ?? '', url: session?.companyLogo, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session?.companyName ?? 'Branch Operations',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  branch?.label ?? 'Your branch',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: const [Padding(padding: EdgeInsets.only(right: 10), child: WalletChip())],
    );
  }
}

/// Wallet balance pill. Hidden when the wallet cannot be read (e.g. a hub user without one).
class WalletChip extends ConsumerWidget {
  const WalletChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(branchWalletProvider);
    return switch (wallet) {
      AsyncData(value: final w?) => Tooltip(
        message: 'Branch wallet: available balance',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => ref.invalidate(branchWalletProvider),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  Fmt.money(w.available),
                  style: TextStyle(
                    color: w.available < 0 ? const Color(0xFFFFCDD2) : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      AsyncLoading() => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Company logo from the session (a URL on the server), or the company's initials.
class CompanyLogo extends ConsumerWidget {
  const CompanyLogo({super.key, required this.name, this.url, this.size = 36});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(
        initials.isEmpty ? 'CS' : initials.toUpperCase(),
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: size * 0.38),
      ),
    );
    final raw = url;
    if (raw == null || raw.isEmpty) return fallback;
    // A path on our own server needs the base URL and the user's token.
    final sameServer = raw.startsWith('/');
    final full = sameServer ? '${Env.apiBaseUrl}$raw' : raw;
    final token = sameServer ? ref.watch(sessionProvider)?.accessToken : null;
    final headers = token == null ? null : {'Authorization': 'Bearer $token'};
    // Logos may be uploaded as SVG (the server accepts PNG/JPEG/SVG/WEBP/ICO);
    // Image.network cannot draw SVG.
    final isSvg = Uri.tryParse(full)?.path.toLowerCase().endsWith('.svg') ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Container(
        width: size,
        height: size,
        color: AppColors.surface,
        padding: const EdgeInsets.all(2),
        child: isSvg
            ? SvgPicture.network(
                full,
                fit: BoxFit.contain,
                headers: headers,
                placeholderBuilder: (_) => fallback,
                errorBuilder: (_, _, _) => fallback,
              )
            : Image.network(full, fit: BoxFit.contain, headers: headers, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

/// White section bar for a tab's own title (and tabs) under the branch header.
PreferredSizeWidget sectionBar(String title, {List<Widget>? actions, PreferredSizeWidget? bottom}) => AppBar(
  title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
  automaticallyImplyLeading: false,
  backgroundColor: AppColors.surface,
  foregroundColor: AppColors.textPrimary,
  surfaceTintColor: Colors.transparent,
  toolbarHeight: 48,
  elevation: 0,
  shape: const Border(bottom: BorderSide(color: AppColors.border)),
  actions: actions,
  bottom: bottom,
);

/// Tab bar coloured for [sectionBar].
TabBar sectionTabs(List<Widget> tabs) => TabBar(
  labelColor: AppColors.primary,
  unselectedLabelColor: AppColors.textSecondary,
  indicatorColor: AppColors.primary,
  tabs: tabs,
);
