// Scanned values. A shipment label's barcode / QR holds a package id
// (`<AWB>-001`, `<AWB>-002`, ...), same scheme as the web label print; a
// typed value is usually the AWB or the shipment number.

final _packageId = RegExp(r'^(.+)-(\d{3})$');

/// The AWB inside a package id, or null when [raw] is not one.
String? awbFromPackageId(String raw) => _packageId.firstMatch(raw.trim())?.group(1);

/// A tracking link (`https://.../track/<number>`) carries the number in its last path part.
String _fromLink(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.pathSegments.isEmpty) return raw;
  final i = uri.pathSegments.indexOf('track');
  return i >= 0 && i + 1 < uri.pathSegments.length ? uri.pathSegments[i + 1] : uri.pathSegments.last;
}

/// Values a scan could mean, most specific first: itself, then its AWB.
List<String> scanCandidates(String raw) {
  final r = _fromLink(raw.trim());
  final awb = awbFromPackageId(r);
  return awb == null ? [r] : [r, awb];
}

/// True when a scanned or typed value names this shipment (case-insensitive).
bool matchesScan({required String trackingNumber, required String shipmentNumber, required String raw}) {
  final c = scanCandidates(raw).map((s) => s.toLowerCase());
  return c.contains(trackingNumber.toLowerCase()) || c.contains(shipmentNumber.toLowerCase());
}
