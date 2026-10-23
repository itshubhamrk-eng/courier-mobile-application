import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/widgets/state_views.dart';

/// Opens a generated PDF with the system print and share actions.
Future<void> openDocument(
  BuildContext context, {
  required String title,
  required String fileName,
  required Future<Uint8List> Function() build,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => DocumentPage(title: title, fileName: fileName, build: build),
  ),
);

class DocumentPage extends StatefulWidget {
  const DocumentPage({super.key, required this.title, required this.fileName, required this.build});

  final String title;
  final String fileName;
  final Future<Uint8List> Function() build;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  late Future<Uint8List> _pdf = widget.build();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<Uint8List>(
      future: _pdf,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: () => setState(() => _pdf = widget.build()));
        }
        if (!snap.hasData) return const LoadingView(message: 'Preparing document…');
        final bytes = snap.data!;
        return PdfPreview(
          build: (_) => bytes,
          pdfFileName: widget.fileName,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          allowPrinting: true,
          allowSharing: true,
        );
      },
    ),
  );
}
