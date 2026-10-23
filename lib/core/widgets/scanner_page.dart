import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen barcode / QR scanner. Pops with the first scanned value.
///
/// The value is only an AWB candidate: callers look it up on the server and
/// check eligibility before using it.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.title = 'Scan AWB'});

  final String title;

  static Future<String?> scan(BuildContext context, {String title = 'Scan AWB'}) =>
      Navigator.of(context)
          .push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScannerPage(title: title)));

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value = capture.barcodes.map((b) => b.rawValue?.trim()).nonNulls.where((v) => v.isNotEmpty).firstOrNull;
    if (value == null) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: Text(widget.title),
      actions: [IconButton(tooltip: 'Torch', icon: const Icon(Icons.flash_on), onPressed: _controller.toggleTorch)],
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Camera permission is needed to scan. Allow it in Settings, or type the AWB instead.'
                    : 'Camera could not start. Type the AWB instead.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 260,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Text(
            'Point the camera at the AWB barcode or QR code',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}
