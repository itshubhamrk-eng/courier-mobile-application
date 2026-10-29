import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/env.dart';
import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../masters/data/masters.dart';
import '../application/wallet_state.dart';
import '../data/wallet_models.dart';
import '../data/wallet_repository.dart';
import 'wallet_widgets.dart';

/// A branch asks its company admin to fund the wallet (cash deposit, bank transfer).
/// A proof image is mandatory; nothing is credited until the admin approves.
class TopupRequestPage extends ConsumerStatefulWidget {
  const TopupRequestPage({super.key});

  @override
  ConsumerState<TopupRequestPage> createState() => _TopupRequestPageState();
}

class _TopupRequestPageState extends ConsumerState<TopupRequestPage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _remarks = TextEditingController();
  Uint8List? _proof;
  bool _proofMissing = false;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() {
        _proof = bytes;
        _proofMissing = false;
      });
    }
  }

  Future<void> _send() async {
    final valid = _form.currentState!.validate();
    setState(() => _proofMissing = _proof == null);
    if (_busy || !valid || _proof == null) return;
    setState(() => _busy = true);
    final repo = ref.read(walletRepositoryProvider);
    try {
      final url = await repo.uploadTopupProof(_proof!, 'topup-proof-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await repo.createTopupRequest(
        branchId: ref.read(walletBranchProvider),
        amount: num.parse(_amount.text),
        remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
        proofImageUrl: url,
      );
      if (!mounted) return;
      ref.invalidate(_topupsProvider);
      showSuccess(context, 'Top-up request sent to your company admin.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showFailure(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider).value;
    return Scaffold(
      appBar: AppBar(flexibleSpace: const AppBarGradient(), title: const Text('Request Top-up')),
      body: !ref.watch(walletAccessProvider).requestTopup
          ? const EmptyView(message: 'Only a branch manager can request a top-up.', icon: Icons.lock_outline)
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'Amount',
                    icon: Icons.currency_rupee,
                    color: AppColors.indigo,
                    children: [
                      Text(
                        '${wallet?.branchName ?? 'Your branch'} · sent to your company admin for approval',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      AmountField(controller: _amount, decimals: true, max: 10000000),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _remarks,
                        maxLength: 300,
                        decoration: const InputDecoration(
                          labelText: 'Remarks',
                          hintText: 'Why the branch needs it, deposit details…',
                        ),
                      ),
                    ],
                  ),
                  SectionCard(
                    title: 'Proof of payment',
                    icon: Icons.photo_camera_outlined,
                    color: AppColors.pink,
                    children: [
                      const Text(
                        'Photo of the cash deposit slip or transfer screenshot. Required.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      if (_proof != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(_proof!, height: 200, fit: BoxFit.cover),
                        ),
                      if (_proofMissing)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Add a proof image before sending.',
                            style: TextStyle(color: AppColors.danger, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _pick(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(_proof == null ? 'Take photo' : 'Retake'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Gallery'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                    label: Text(_busy ? 'Sending…' : 'Send request'),
                  ),
                ],
              ),
            ),
    );
  }
}

typedef _TopupKey = ({String? branchId, String? status});

final _topupsProvider = FutureProvider.autoDispose.family<List<TopupRequest>, _TopupKey>(
  (ref, k) async =>
      (await ref.watch(walletRepositoryProvider).topupRequests(branchId: k.branchId, status: k.status)).content,
);

/// Branch: its own requests and their status. Company admin: every branch's, with
/// approve / reject on pending ones.
class TopupRequestsPage extends ConsumerStatefulWidget {
  const TopupRequestsPage({super.key});

  @override
  ConsumerState<TopupRequestsPage> createState() => _TopupRequestsPageState();
}

class _TopupRequestsPageState extends ConsumerState<TopupRequestsPage> {
  String? _status = 'PENDING';
  String? _branchId;
  String? _deciding;

  Future<void> _decide(TopupRequest r, bool approve) async {
    final remarks = await _askRemarks(approve);
    if (remarks == null || !mounted) return;
    setState(() => _deciding = r.id);
    try {
      await ref
          .read(walletRepositoryProvider)
          .decideTopup(r.id, approve: approve, remarks: remarks.isEmpty ? null : remarks);
      if (!mounted) return;
      refreshWallet(ref);
      ref.invalidate(_topupsProvider);
      showSuccess(context, approve ? 'Approved: ${Fmt.money(r.amount)} credited.' : 'Request rejected.');
    } on ApiException catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  /// Null when cancelled; empty string for "no remarks".
  Future<String?> _askRemarks(bool approve) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(approve ? 'Approve top-up?' : 'Reject top-up?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(approve ? 'The amount is credited to the branch wallet.' : 'Nothing is credited.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Remarks (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: approve ? AppColors.success : AppColors.danger),
            onPressed: () => Navigator.pop(d, c.text.trim()),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(walletAccessProvider);
    final key = (branchId: access.admin ? _branchId : null, status: _status);
    final rows = ref.watch(_topupsProvider(key));
    final branches = <String, String>{
      for (final b in ref.watch(branchDirectoryProvider).value ?? const <Branch>[]) b.id: b.label,
    };
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const AppBarGradient(),
        title: const Text('Top-up Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_topupsProvider),
          ),
        ],
      ),
      floatingActionButton: access.requestTopup
          ? FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TopupRequestPage())),
              icon: const Icon(Icons.send),
              label: const Text('Request'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_topupsProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              access.admin
                  ? 'Branches ask to fund their wallet. Approve to credit, reject to decline.'
                  : "Your branch's top-up requests and their status.",
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (value, label) in const [
                    ('PENDING', 'Pending'),
                    ('APPROVED', 'Approved'),
                    ('REJECTED', 'Rejected'),
                    (null, 'All'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _status == value,
                        onSelected: (_) => setState(() => _status = value),
                      ),
                    ),
                ],
              ),
            ),
            if (access.admin) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Branch', prefixIcon: Icon(Icons.store_outlined)),
                items: [
                  const DropdownMenuItem<String?>(child: Text('All branches')),
                  for (final e in branches.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _branchId = v),
              ),
            ],
            const SizedBox(height: 12),
            switch (rows) {
              AsyncData(:final value) when value.isEmpty => const EmptyView(
                message: 'No requests match.',
                icon: Icons.fact_check_outlined,
              ),
              AsyncData(:final value) => Column(
                children: [
                  for (final r in value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AccentCard(
                        color: statusStyle(r.status).color,
                        icon: Icons.account_balance_wallet_outlined,
                        title: Fmt.money(r.amount),
                        trailing: StatusBadge(r.status),
                        children: [
                          if (access.admin && branches[r.branchId] != null)
                            Text(branches[r.branchId]!, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            'Requested ${Fmt.dateTime(r.createdAt)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          if (r.remarks != null) Text(r.remarks!, style: const TextStyle(fontSize: 13)),
                          if (r.decidedAt != null)
                            Text(
                              'Decided ${Fmt.dateTime(r.decidedAt)}'
                              '${r.decisionRemarks == null ? '' : ': ${r.decisionRemarks}'}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (r.proofImageUrl != null)
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                                  onPressed: () => _openProof(context, ref, r.proofImageUrl!),
                                  icon: const Icon(Icons.image_outlined, size: 18),
                                  label: const Text('Proof'),
                                ),
                              if (access.admin && r.status == 'PENDING') ...[
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    foregroundColor: AppColors.danger,
                                    side: const BorderSide(color: AppColors.danger),
                                  ),
                                  onPressed: _deciding == null ? () => _decide(r, false) : null,
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('Reject'),
                                ),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    backgroundColor: AppColors.success,
                                  ),
                                  onPressed: _deciding == null ? () => _decide(r, true) : null,
                                  icon: _deciding == r.id
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.check, size: 18),
                                  label: const Text('Approve'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(_topupsProvider)),
              _ => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// Shows an uploaded proof image (server-relative URLs carry the session token).
Future<void> _openProof(BuildContext context, WidgetRef ref, String url) {
  final sameServer = url.startsWith('/');
  final full = sameServer ? '${Env.apiBaseUrl}$url' : url;
  final token = sameServer ? ref.read(sessionProvider)?.accessToken : null;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(flexibleSpace: const AppBarGradient(), title: const Text('Proof of payment')),
        backgroundColor: Colors.black,
        body: InteractiveViewer(
          child: Center(
            child: Image.network(
              full,
              headers: token == null ? null : {'Authorization': 'Bearer $token'},
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'The proof image could not be loaded.',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
