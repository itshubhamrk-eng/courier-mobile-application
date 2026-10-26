import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/ui.dart';
import '../application/wallet_state.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';
import 'wallet_widgets.dart';

/// The wallet ledger: paged, searchable, filterable, exportable (web: Wallet Transactions).
class WalletTransactionsPage extends ConsumerStatefulWidget {
  const WalletTransactionsPage({super.key});

  @override
  ConsumerState<WalletTransactionsPage> createState() => _WalletTransactionsPageState();
}

class _WalletTransactionsPageState extends ConsumerState<WalletTransactionsPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  TxnFilter _filter = const TxnFilter();
  final List<WalletTxn> _rows = [];
  int _page = 0;
  int _total = 0;
  bool _hasNext = true;
  bool _loading = false;
  bool _exporting = false;
  Object? _error;

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
    if (_loading || (!reset && !_hasNext)) return;
    final branchId = ref.read(walletBranchProvider);
    final filter = _filter;
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
          .transactions(branchId: branchId, filter: filter, page: _page);
      if (!mounted || filter != _filter) return;
      setState(() {
        _rows.addAll(res.content);
        _total = res.totalElements;
        _hasNext = res.hasNext;
        _page++;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _filter = _filter.copyWith(search: v);
      _loading = false;
      _load(reset: true);
    });
  }

  Future<void> _openFilters() async {
    final f = await showModalBottomSheet<TxnFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (f == null) return;
    _filter = TxnFilter(
      search: _filter.search,
      from: f.from,
      to: f.to,
      types: f.types,
      subTypes: f.subTypes,
      reference: f.reference,
    );
    _loading = false;
    await _load(reset: true);
  }

  /// Walks every page (size 100, the server cap) and shares a CSV, as the web export does.
  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final repo = ref.read(walletRepositoryProvider);
      final branchId = ref.read(walletBranchProvider);
      final all = <WalletTxn>[];
      for (var p = 0; p < 50; p++) {
        final res = await repo.transactions(branchId: branchId, filter: _filter, page: p, size: 100);
        all.addAll(res.content);
        if (!res.hasNext) break;
      }
      String cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final csv = StringBuffer(
        'Transaction No,Date,Type,Reason,Amount,Balance Before,Balance After,Reference Type,Reference,'
        'Payment Reference,Remarks,Created By\n',
      );
      for (final t in all) {
        csv.writeln(
          [
            t.transactionNo,
            t.createdAt.toLocal().toIso8601String(),
            t.isCredit ? 'CR' : 'DR',
            t.reason,
            t.amount,
            t.balanceBefore,
            t.balanceAfter,
            t.referenceType,
            t.referenceId,
            t.paymentReference,
            t.remarks,
            t.createdByName,
          ].map(cell).join(','),
        );
      }
      final name = 'wallet-transactions-${Fmt.apiDate(DateTime.now())}.csv';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(csv.toString()), mimeType: 'text/csv', name: name)],
          fileNameOverrides: [name],
          subject: 'Wallet transactions',
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
    final wallet = ref.watch(walletProvider).value;
    final active = _filter.activeCount;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const AppBarGradient(),
        title: const Text('Wallet Transactions'),
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
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      hintText: 'Search transaction no, reference…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Badge(
                  isLabelVisible: active > 0,
                  label: Text('$active'),
                  child: IconButton.filledTonal(
                    tooltip: 'Filters',
                    onPressed: _openFilters,
                    icon: const Icon(Icons.filter_list),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$_total entries${wallet?.branchName == null ? '' : ' · ${wallet!.branchName}'}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (final t in _rows)
              TxnTile(
                txn: t,
                onTap: () => showTxnDetail(context, ref, t, wallet: wallet),
              ),
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
              const EmptyView(message: 'No transactions match.', icon: Icons.receipt_long_outlined),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final TxnFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;
  late final Set<String> _types = {...widget.initial.types};
  late final Set<String> _subTypes = {...widget.initial.subTypes};
  late final _reference = TextEditingController(text: widget.initial.reference);

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDate: (from ? _from : _to) ?? now,
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Filters', icon: Icons.filter_list, color: AppColors.indigo),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _DateBox('From', _from, () => _pickDate(true))),
              const SizedBox(width: 10),
              Expanded(child: _DateBox('To', _to, () => _pickDate(false))),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Type', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final (code, label) in const [('CR', 'Credit'), ('DR', 'Debit')])
                FilterChip(
                  label: Text(label),
                  selected: _types.contains(code),
                  onSelected: (v) => setState(() => v ? _types.add(code) : _types.remove(code)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Reason', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final code in subTypeLabels.keys)
                FilterChip(
                  label: Text(subTypeLabel(code)),
                  selected: _subTypes.contains(code),
                  onSelected: (v) => setState(() => v ? _subTypes.add(code) : _subTypes.remove(code)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(labelText: 'Reference', hintText: 'e.g. RZP-XXXX / UTR'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, const TxnFilter()),
                  child: const Text('Clear all'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    TxnFilter(from: _from, to: _to, types: _types, subTypes: _subTypes, reference: _reference.text),
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DateBox extends StatelessWidget {
  const _DateBox(this.label, this.value, this.onTap);

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event_outlined)),
      child: Text(value == null ? 'Any' : Fmt.date(value)),
    ),
  );
}
