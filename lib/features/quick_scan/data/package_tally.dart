import '../../../core/scan_code.dart';

/// What one scan did to a [PackageTally].
enum ScanAck { added, duplicate, wrongShipment, needsPackage, outOfRange }

/// Which packages of one shipment have been scanned. A label carries its own package
/// id (`<AWB>-001`), so the same label can never be counted twice.
class PackageTally {
  PackageTally({required this.trackingNumber, required this.shipmentNumber, required int quantity})
    : quantity = quantity < 1 ? 1 : quantity;

  final String trackingNumber;
  final String shipmentNumber;
  final int quantity;
  final Set<int> scanned = {};

  bool get complete => scanned.length == quantity;
  List<int> get missing => [
    for (var n = 1; n <= quantity; n++)
      if (!scanned.contains(n)) n,
  ];
  List<String> get missingIds => missing.map(packageId).toList();

  String packageId(int n) => '$trackingNumber-${n.toString().padLeft(3, '0')}';

  /// Counts a scanned or typed value. A shipment-level code (AWB, shipment number,
  /// tracking link) names no package, so it only counts when there is just one.
  /// [typed] also accepts the bare package number (an unreadable label).
  ScanAck scan(String raw, {bool typed = false}) {
    final value = scanCandidates(raw).first;
    if (matchesScan(trackingNumber: trackingNumber, shipmentNumber: shipmentNumber, raw: value) &&
        awbFromPackageId(value)?.toLowerCase() != trackingNumber.toLowerCase()) {
      return quantity == 1 ? _add(1) : ScanAck.needsPackage;
    }
    if (awbFromPackageId(value)?.toLowerCase() == trackingNumber.toLowerCase()) {
      return _add(int.parse(value.substring(value.length - 3)));
    }
    if (typed && RegExp(r'^\d{1,3}$').hasMatch(value)) return _add(int.parse(value));
    return ScanAck.wrongShipment;
  }

  ScanAck _add(int n) {
    if (n < 1 || n > quantity) return ScanAck.outOfRange;
    return scanned.add(n) ? ScanAck.added : ScanAck.duplicate;
  }
}
