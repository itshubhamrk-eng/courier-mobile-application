import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/ui.dart';
import '../../documents/document_page.dart';
import '../../documents/document_service.dart';
import '../../shell/branch_header.dart';
import '../application/wallet_state.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';

/// Large rupee amount input used by recharge, top-up and manual credit / debit.
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.max = 999999, this.decimals = false, this.onChanged});

  final TextEditingController controller;
  final num max;
  final bool decimals;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: decimals),
    inputFormatters: [
      FilteringTextInputFormatter.allow(decimals ? RegExp(r'^\d{0,7}(\.\d{0,2})?') : RegExp(r'\d')),
      if (!decimals) LengthLimitingTextInputFormatter(6),
    ],
    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
    decoration: const InputDecoration(
      labelText: 'Amount',
      prefixText: '₹ ',
      prefixStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
    ),
    onChanged: onChanged,
    validator: (v) {
      final n = num.tryParse(v ?? '');
      if (n == null || n <= 0) return 'Enter an amount';
      if (n > max) return 'Enter an amount up to ${Fmt.money(max)}';
      return null;
    },
  );
}

/// Balance / figure tile on the wallet dashboard.
class BalanceTile extends StatelessWidget {
  const BalanceTile({
    super.key,
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    this.hint,
  });

  final String label;
  final num amount;
  final IconData icon;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            Fmt.money(amount),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
      ],
    ),
  );
}

/// One ledger row: direction icon, reason, number, signed amount, balance after.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, required this.onTap});

  final WalletTxn txn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = txn.isCredit ? AppColors.success : AppColors.danger;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconBadge(txn.isCredit ? Icons.south_west : Icons.north_east, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(txn.reason, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${txn.transactionNo} · ${Fmt.dateTime(txn.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (txn.remarks != null)
                      Text(
                        txn.remarks!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${txn.isCredit ? '+' : '−'}${Fmt.money(txn.amount)}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: color),
                  ),
                  Text(
                    'Bal ${Fmt.money(txn.balanceAfter)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the receipt PDF for a ledger entry (print / share from the viewer).
Future<void> openReceipt(BuildContext context, WidgetRef ref, WalletTxn t, {Wallet? wallet}) => openDocument(
  context,
  title: 'Receipt ${t.transactionNo}',
  fileName: 'receipt-${t.transactionNo}.pdf',
  build: () => ref
      .read(documentServiceProvider)
      .walletReceipt(t, walletNumber: wallet?.walletNumber, branchName: wallet?.branchName),
);

/// Full details of a ledger entry, with Receipt.
Future<void> showTxnDetail(BuildContext context, WidgetRef ref, WalletTxn t, {Wallet? wallet}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  '${t.isCredit ? '+' : '−'}${Fmt.money(t.amount)}',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: t.isCredit ? AppColors.success : AppColors.danger,
                  ),
                ),
              ),
              Center(
                child: Text(t.reason, style: const TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 12),
              InfoRow('Transaction no', t.transactionNo),
              InfoRow('Date & time', Fmt.dateTime(t.createdAt)),
              InfoRow('Type', t.typeLabel ?? (t.isCredit ? 'Credit' : 'Debit')),
              InfoRow('Balance before', Fmt.money(t.balanceBefore)),
              InfoRow('Balance after', Fmt.money(t.balanceAfter)),
              InfoRow('Reference type', prettyToken(t.referenceType)),
              InfoRow('Reference', t.referenceId),
              InfoRow('Payment gateway', t.paymentGateway),
              InfoRow('Payment reference', t.paymentReference),
              InfoRow('Remarks', t.remarks),
              InfoRow('Created by', t.createdByName),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  openReceipt(context, ref, t, wallet: wallet);
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Receipt'),
              ),
            ],
          ),
        ),
      ),
    );

/// Company admin's manual credit / debit (offline money, corrections). Returns the entry.
Future<WalletTxn?> showManualMoneySheet(BuildContext context, {required bool credit, required Wallet wallet}) =>
    showModalBottomSheet<WalletTxn>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ManualMoneySheet(credit: credit, wallet: wallet),
    );

class _ManualMoneySheet extends ConsumerStatefulWidget {
  const _ManualMoneySheet({required this.credit, required this.wallet});

  final bool credit;
  final Wallet wallet;

  @override
  ConsumerState<_ManualMoneySheet> createState() => _ManualMoneySheetState();
}

class _ManualMoneySheetState extends ConsumerState<_ManualMoneySheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _remarks = TextEditingController();
  late String _subType = widget.credit ? 'MCR' : 'MDB';
  String? _referenceType;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final amount = num.parse(_amount.text);
    final ok = await confirmAction(
      context,
      title: widget.credit ? 'Credit wallet?' : 'Debit wallet?',
      message:
          '${widget.credit ? 'Add' : 'Take'} ${Fmt.money(amount)} ${widget.credit ? 'to' : 'from'} '
          '${widget.wallet.branchName ?? widget.wallet.walletNumber} as ${subTypeLabel(_subType)}.',
      confirmLabel: widget.credit ? 'Credit' : 'Debit',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final t = await ref
          .read(walletRepositoryProvider)
          .manual(
            credit: widget.credit,
            branchId: widget.wallet.branchId,
            amount: amount,
            subType: _subType,
            referenceType: _referenceType,
            referenceId: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
          );
      if (mounted) Navigator.pop(context, t);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = widget.credit ? creditSubTypes : debitSubTypes;
    final color = widget.credit ? AppColors.success : AppColors.danger;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                widget.credit ? 'Credit wallet' : 'Debit wallet',
                icon: widget.credit ? Icons.add : Icons.remove,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.wallet.branchName ?? ''} · ${widget.wallet.walletNumber} · '
                'available ${Fmt.money(widget.wallet.available)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              AmountField(controller: _amount, decimals: true, max: 10000000),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _subType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: [for (final t in types) DropdownMenuItem(value: t, child: Text(subTypeLabel(t)))],
                onChanged: (v) => setState(() => _subType = v ?? _subType),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _referenceType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reference type (optional)'),
                items: [
                  const DropdownMenuItem<String?>(child: Text('None')),
                  for (final t in referenceTypes) DropdownMenuItem(value: t, child: Text(prettyToken(t))),
                ],
                onChanged: (v) => setState(() => _referenceType = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reference,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Reference (optional)', hintText: 'UTR, receipt no…'),
              ),
              TextFormField(
                controller: _remarks,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Remarks (optional)'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Icon(widget.credit ? Icons.add : Icons.remove),
                label: Text(widget.credit ? 'Credit wallet' : 'Debit wallet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Invalidates everything that shows a balance, after money moved.
void refreshWallet(WidgetRef ref) {
  ref.invalidate(walletProvider);
  ref.invalidate(walletSummaryProvider);
  ref.invalidate(recentTxnsProvider);
  ref.invalidate(branchWalletProvider);
}
