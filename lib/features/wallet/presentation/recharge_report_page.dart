import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/ui.dart';
import '../application/wallet_state.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';
import 'wallet_widgets.dart';

/// Every recharge, online (Razorpay) and manual, by outcome (web: Wallet Recharge Report).
/// Pending online ones are re-checked by the server every 2 minutes; "Check status"
/// asks the gateway now. Credited online ones show the bank settlement.
class RechargeReportPage extends ConsumerStatefulWidget {
  const RechargeReportPage({super.key});

  @override
  ConsumerState<RechargeReportPage> createState() => _RechargeReportPageState();
}

class _RechargeReportPageState extends ConsumerState<RechargeReportPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _mode;
  String? _status;
  DateTime? _from;
  DateTime? _to;
  final List<RechargeAttempt> _rows = [];
  int _page = 0;
  int _total = 0;
  bool _hasNext = true;
  bool _loading = false;
  bool _exporting = false;
  String? _checking;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _generation++;
      _loading = false;
    }
    if (_loading || (!reset && !_hasNext)) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _rows.clear();
        _page = 0;
        _hasNext = true;
      }
    });
    try {
      final res = await ref
          .read(walletRepositoryProvider)
          .rechargeReport(status: _status, mode: _mode, from: _from, to: _to, search: _search.text, page: _page);
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows.addAll(res.content);
        _total = res.totalElements;
        _hasNext = res.hasNext;
        _page++;
      });
    } on ApiException catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _check(RechargeAttempt a) async {
    setState(() => _checking = a.id);
    try {
      final updated = await ref.read(walletRepositoryProvider).checkAttempt(a.id);
      if (!mounted) return;
      final i = _rows.indexWhere((r) => r.id == a.id);
      if (i >= 0) setState(() => _rows[i] = updated);
      if (updated.status == 'SUCCESS' && a.status != 'SUCCESS') {
        refreshWallet(ref);
        showSuccess(context, 'Payment confirmed: ${Fmt.money(updated.amount)} credited.');
      } else if (updated.status == 'FAILED' && a.status != 'FAILED') {
        showFailure(context, ApiException(ApiErrorKind.validation, updated.failureReason ?? 'Payment failed.'));
      } else if (updated.bankSettlementStatus == 'SETTLED' && a.bankSettlementStatus != 'SETTLED') {
        showSuccess(context, 'Settled to bank.');
      } else {
        showSuccess(context, 'No change yet. The gateway has not confirmed it.');
      }
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _checking = null);
    }
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDate: (from ? _from : _to) ?? now,
    );
    if (d == null) return;
    setState(() => from ? _from = d : _to = d);
    await _load(reset: true);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final repo = ref.read(walletRepositoryProvider);
      final all = <RechargeAttempt>[];
      for (var p = 0; p < 50; p++) {
        final res = await repo.rechargeReport(
          status: _status,
          mode: _mode,
          from: _from,
          to: _to,
          search: _search.text,
          page: p,
          size: 100,
        );
        all.addAll(res.content);
        if (!res.hasNext) break;
      }
      String cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final csv = StringBuffer(
        'Date,Branch,Transaction No,Mode,Amount,Status,Reason / Remarks,Order ID,Payment ID,Recorded By,'
        'Settled At,Bank Settlement,UTR\n',
      );
      for (final a in all) {
        csv.writeln(
          [
            a.createdAt.toLocal().toIso8601String(),
            a.branchName,
            a.transactionNo,
            a.mode == 'ONLINE' ? 'Razorpay' : 'Manual',
            a.amount,
            a.status,
            a.failureReason ?? a.remarks,
            a.gatewayOrderId,
            a.gatewayPaymentId,
            a.recordedByName,
            a.settledAt?.toLocal().toIso8601String(),
            a.bankSettlementStatus,
            a.bankSettlementUtr,
          ].map(cell).join(','),
        );
      }
      final name = 'recharge-report-${Fmt.apiDate(DateTime.now())}.csv';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(csv.toString()), mimeType: 'text/csv', name: name)],
          fileNameOverrides: [name],
          subject: 'Wallet recharge report',
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(walletAccessProvider);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const AppBarGradient(),
        title: const Text('Recharge Report'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: access.recharge
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/wallet/recharge');
                if (mounted) await _load(reset: true);
              },
              icon: const Icon(Icons.add_card),
              label: const Text('Recharge'),
            )
          : null,
      body: !access.rechargeReport
          ? const EmptyView(message: 'Your role cannot view the recharge report.', icon: Icons.lock_outline)
          : RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
                    },
                    decoration: const InputDecoration(
                      hintText: 'Search transaction no, order or payment id…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Chips(
                    options: const [(null, 'All modes'), ('ONLINE', 'Razorpay'), ('MANUAL', 'Manual')],
                    selected: _mode,
                    onSelected: (v) {
                      setState(() => _mode = v);
                      _load(reset: true);
                    },
                  ),
                  const SizedBox(height: 6),
                  _Chips(
                    options: const [
                      (null, 'All'),
                      ('PENDING', 'Pending'),
                      ('SUCCESS', 'Success'),
                      ('FAILED', 'Failed'),
                    ],
                    selected: _status,
                    onSelected: (v) {
                      setState(() => _status = v);
                      _load(reset: true);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _DateChip('From', _from, () => _pickDate(true))),
                      const SizedBox(width: 8),
                      Expanded(child: _DateChip('To', _to, () => _pickDate(false))),
                      if (_from != null || _to != null)
                        IconButton(
                          tooltip: 'Clear dates',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() => _from = _to = null);
                            _load(reset: true);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_total entries · pending ones are re-checked every 2 minutes',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  for (final a in _rows) _AttemptCard(a: a, checking: _checking, onCheck: () => _check(a)),
                  if (_error != null)
                    ErrorView(
                      error: _error!,
                      onRetry: () => _load(reset: _rows.isEmpty),
                    )
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_rows.isEmpty)
                    const EmptyView(
                      message: 'No recharge attempts. An online recharge started from the wallet appears here.',
                      icon: Icons.assessment_outlined,
                    ),
                ],
              ),
            ),
    );
  }
}

class _AttemptCard extends StatelessWidget {
  const _AttemptCard({required this.a, required this.checking, required this.onCheck});

  final RechargeAttempt a;
  final String? checking;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final online = a.mode == 'ONLINE';
    final note = a.failureReason ?? a.remarks ?? (a.status == 'PENDING' ? 'Waiting for the gateway' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AccentCard(
        color: statusStyle(a.status).color,
        icon: online ? Icons.credit_card : Icons.edit_note,
        title: Fmt.money(a.amount),
        trailing: StatusBadge(a.status),
        children: [
          Text(
            '${a.transactionNo} · ${online ? 'Razorpay' : 'Manual'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            [?a.branchName, Fmt.dateTime(a.createdAt)].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  color: a.failureReason != null ? AppColors.danger : AppColors.textSecondary,
                ),
              ),
            ),
          if (a.gatewayOrderId != null || a.gatewayPaymentId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  if (a.gatewayOrderId != null) 'Order ${a.gatewayOrderId}',
                  if (a.gatewayPaymentId != null) 'Payment ${a.gatewayPaymentId}',
                ].join('\n'),
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace'),
              ),
            ),
          if (a.recordedByName != null)
            Text('By ${a.recordedByName}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (a.settledAt != null)
            Text(
              'Credited ${Fmt.dateTime(a.settledAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.success),
            )
          else if (a.lastCheckedAt != null)
            Text(
              'Last checked ${Fmt.dateTime(a.lastCheckedAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          if (a.bankSettlementStatus != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                StatusBadge(a.bankSettlementStatus!),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.bankSettlementStatus == 'SETTLED'
                        ? [
                            Fmt.date(a.bankSettledAt),
                            if (a.bankSettlementUtr != null) 'UTR ${a.bankSettlementUtr}',
                          ].join(' · ')
                        : (a.settlementLastCheckedAt == null
                              ? ''
                              : 'checked ${Fmt.dateTime(a.settlementLastCheckedAt)}'),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (a.canCheck) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                onPressed: checking == null ? onCheck : null,
                icon: checking == a.id
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync, size: 18),
                label: Text(a.status == 'PENDING' ? 'Check status' : 'Check settlement'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.selected, required this.onSelected});

  final List<(String?, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (value, label) in options)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(label), selected: selected == value, onSelected: (_) => onSelected(value)),
          ),
      ],
    ),
  );
}

class _DateChip extends StatelessWidget {
  const _DateChip(this.label, this.value, this.onTap);

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: const Icon(Icons.event_outlined, size: 18),
    label: Text('$label: ${value == null ? 'Any' : Fmt.date(value)}'),
    onPressed: onTap,
  );
}
