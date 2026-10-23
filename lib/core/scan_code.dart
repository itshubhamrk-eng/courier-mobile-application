// Scanned values. A shipment label's barcode / QR holds a package id
// (`<AWB>-001`, `<AWB>-002`, ...), same scheme as the web label print; a
// typed value is usually the AWB or the shipment number.

final _packageId = RegExp(r'^(.+)-(\d{3})$');

/// The AWB inside a package id, or null when [raw] is not one.
String? awbFromPackageId(String raw) => _packageId.firstMatch(raw.trim())?.group(1);

/// Values a scan could mean, most specific first: itself, then its AWB.
List<String> scanCandidates(String raw) {
  final r = raw.trim();
  final awb = awbFromPackageId(r);
  return awb == null ? [r] : [r, awb];
}

/// True when a scanned or typed value names this shipment (case-insensitive).
bool matchesScan({required String trackingNumber, required String shipmentNumber, required String raw}) {
  final c = scanCandidates(raw).map((s) => s.toLowerCase());
  return c.contains(trackingNumber.toLowerCase()) || c.contains(shipmentNumber.toLowerCase());
}
