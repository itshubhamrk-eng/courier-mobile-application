import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/ui.dart';
import '../data/party_text.dart';

const _channel = MethodChannel('branch_ops/text_reader');

/// Takes or picks a photo; null when cancelled. Overridable in tests.
final photoPathProvider = Provider<Future<String?> Function(ImageSource source)>(
  (ref) =>
      (source) async => (await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2400))?.path,
);

/// Reads the text of a photo on the phone and deletes the photo: it is never uploaded.
final photoTextProvider = Provider<Future<List<TextLine>> Function(String path)>(
  (ref) => (path) async {
    try {
      final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('read', {'path': path}) ?? const [];
      double n(Map<Object?, Object?> r, String k) => (r[k] as num? ?? 0).toDouble();
      return [
        for (final r in rows)
          TextLine(r['text'] as String, Rect.fromLTRB(n(r, 'left'), n(r, 'top'), n(r, 'right'), n(r, 'bottom'))),
      ];
    } finally {
      // The picker's own cached copy, not the gallery original.
      await File(path).delete().catchError((_) => File(path));
    }
  },
);

/// Photo, then its text split into sender / receiver. Null when cancelled or unreadable
/// (the reason is shown).
Future<PhotoParties?> readPartyPhoto(BuildContext context, WidgetRef ref, PartySide side) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionTitle('${side.label} details from photo', icon: Icons.document_scanner_outlined),
            const SizedBox(height: 8),
            ListTile(
              leading: const IconBadge(Icons.photo_camera_outlined, color: AppColors.indigo),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const IconBadge(Icons.photo_library_outlined, color: AppColors.purple),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  void fail(String message) => showFailure(context, ApiException(ApiErrorKind.validation, message));
  final String? path;
  try {
    path = await ref.read(photoPathProvider)(source);
  } on PlatformException {
    if (context.mounted) fail('The camera could not be opened. Allow camera access in phone settings.');
    return null;
  }
  if (path == null || !context.mounted) return null;

  final navigator = Navigator.of(context, rootNavigator: true);
  final busy = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Reading details…')),
          ],
        ),
      ),
    ),
  );
  navigator.push(busy).ignore();
  try {
    final lines = await ref.read(photoTextProvider)(path);
    final found = parsePhoto(lines, side);
    if (PartySide.values.any(found.has)) return found;
    if (context.mounted) fail('No details could be read. Take a closer, sharper photo in good light.');
  } on PlatformException catch (e) {
    if (context.mounted) {
      fail(
        e.code == 'not_ready'
            ? 'The text reader is still downloading. Stay online and try again in a minute.'
            : 'The photo could not be read. Try again or type the details.',
      );
    }
  } on MissingPluginException {
    if (context.mounted) fail('Reading photos is not available on this device.');
  } finally {
    if (busy.isActive) navigator.removeRoute(busy);
  }
  return null;
}

/// Everything read, editable, before it goes into the form. Null when dismissed.
Future<PartyDetails?> showPartyReview(
  BuildContext context,
  PartySide side,
  PartyDetails found, {
  required PartyDetails current,
  required String rawText,
}) => showModalBottomSheet<PartyDetails>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _ReviewSheet(side: side, found: found, current: current, rawText: rawText),
);

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.side, required this.found, required this.current, required this.rawText});

  final PartySide side;
  final PartyDetails found;
  final PartyDetails current;
  final String rawText;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = _start(widget.found.name, widget.current.name);
  late final _contact = _start(widget.found.contact, widget.current.contact);
  late final _address = _start(widget.found.address, widget.current.address);
  late final _pincode = _start(widget.found.pincode, widget.current.pincode);

  /// What the photo did not give keeps what is already in the form.
  TextEditingController _start(String found, String current) =>
      TextEditingController(text: found.isEmpty ? current : found);

  @override
  void dispose() {
    for (final c in [_name, _contact, _address, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  void _use() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      PartyDetails(
        name: _name.text.trim(),
        contact: _contact.text,
        address: _address.text.trim(),
        pincode: _pincode.text,
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, String found) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    helperText: found.isEmpty ? 'Not found in the photo' : null,
    helperStyle: const TextStyle(color: AppColors.warning),
  );

  @override
  Widget build(BuildContext context) {
    final f = widget.found;
    final digits = FilteringTextInputFormatter.digitsOnly;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle('Check ${widget.side.label.toLowerCase()} details', icon: Icons.fact_check_outlined),
              const SizedBox(height: 4),
              const Text(
                'Correct anything that was read wrong.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Name', Icons.person_outline, f.name),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contact,
                keyboardType: TextInputType.phone,
                inputFormatters: [digits, LengthLimitingTextInputFormatter(10)],
                decoration: _decoration('Mobile number', Icons.phone_outlined, f.contact),
                validator: (v) =>
                    (v ?? '').isEmpty || RegExp(r'^\d{10}$').hasMatch(v!) ? null : 'Enter a 10-digit mobile number',
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 4,
                decoration: _decoration('Address', Icons.home_outlined, f.address),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _pincode,
                keyboardType: TextInputType.number,
                inputFormatters: [digits, LengthLimitingTextInputFormatter(6)],
                decoration: _decoration(
                  widget.side == PartySide.sender ? 'Pickup pincode' : 'Destination pincode',
                  Icons.place_outlined,
                  f.pincode,
                ),
                validator: (v) =>
                    (v ?? '').isEmpty || RegExp(r'^\d{6}$').hasMatch(v!) ? null : 'Enter a 6-digit pincode',
              ),
              const SizedBox(height: 6),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                title: const Text('Text read from the photo', style: TextStyle(fontSize: 14)),
                children: [
                  Align(alignment: Alignment.centerLeft, child: SelectableText(widget.rawText)),
                  const SizedBox(height: 10),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(onPressed: _use, child: const Text('Use details')),
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
