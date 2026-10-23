import '../../../core/format.dart';

class ShipmentSummary {
  const ShipmentSummary({
    required this.id,
    required this.shipmentNumber,
    required this.trackingNumber,
    required this.status,
    this.bookingDate,
    this.fromCity,
    this.toCity,
    this.senderName,
    this.receiverName,
    this.chargeableWeight,
    this.netAmount,
    this.packages,
    this.createdDate,
    this.currentLocationId,
    this.nextLocationId,
    this.deliveryBranchId,
    this.manifestId,
    this.flowType,
    this.receiverContact,
    this.paymentModeId,
  });

  final String id;
  final String shipmentNumber;
  final String trackingNumber;
  final String status;
  final DateTime? bookingDate;
  final String? fromCity;
  final String? toCity;
  final String? senderName;
  final String? receiverName;
  final num? chargeableWeight;
  final num? netAmount;
  final int? packages;
  final DateTime? createdDate;
  final String? currentLocationId;
  final String? nextLocationId;
  final String? deliveryBranchId;
  final String? manifestId;
  final String? flowType;
  final String? receiverContact;
  final String? paymentModeId;

  factory ShipmentSummary.fromJson(Map<String, dynamic> j) => ShipmentSummary(
    id: j['id'] as String,
    shipmentNumber: j['shipmentNumber'] as String? ?? '',
    trackingNumber: j['trackingNumber'] as String? ?? '',
    status: j['status'] as String? ?? '',
    bookingDate: jTime(j['bookingDate']),
    fromCity: jStr(j['fromCity']),
    toCity: jStr(j['toCity']),
    senderName: jStr(j['senderName']),
    receiverName: jStr(j['receiverName']),
    chargeableWeight: jNum(j['chargeableWeight']),
    netAmount: jNum(j['netAmount']),
    packages: jInt(j['numberOfPackages']),
    createdDate: jTime(j['createdDate']),
    currentLocationId: jStr(j['currentLocationId']),
    nextLocationId: jStr(j['nextLocationId']),
    deliveryBranchId: jStr(j['deliveryBranchId']),
    manifestId: jStr(j['manifestId']),
    flowType: jStr(j['flowType']),
    receiverContact: jStr(j['receiverContact']),
    paymentModeId: jStr(j['paymentModeId']),
  );
}

class ShipmentItem {
  const ShipmentItem({this.name, this.quantity, this.weight, this.length, this.width, this.height, this.declaredValue});

  final String? name;
  final int? quantity;
  final num? weight;
  final num? length;
  final num? width;
  final num? height;
  final num? declaredValue;

  factory ShipmentItem.fromJson(Map<String, dynamic> j) => ShipmentItem(
    name: jStr(j['itemName']),
    quantity: jInt(j['quantity']),
    weight: jNum(j['weight']),
    length: jNum(j['lengthCm']),
    width: jNum(j['widthCm']),
    height: jNum(j['heightCm']),
    declaredValue: jNum(j['declaredValue']),
  );
}

class ShipmentDetail {
  const ShipmentDetail({
    required this.id,
    required this.shipmentNumber,
    required this.trackingNumber,
    required this.status,
    required this.raw,
    this.items = const [],
  });

  final String id;
  final String shipmentNumber;
  final String trackingNumber;
  final String status;
  final List<ShipmentItem> items;

  /// Full `ShipmentResponse`, for fields shown as-is.
  final Map<String, dynamic> raw;

  String? s(String key) => jStr(raw[key]);
  num? n(String key) => jNum(raw[key]);
  DateTime? t(String key) => jTime(raw[key]);

  String? get bookingBranchId => s('bookingBranchId');
  String? get deliveryBranchId => s('deliveryBranchId');
  String? get currentLocationId => s('currentLocationId');
  String? get paymentModeId => s('paymentModeId');
  String? get serviceTypeId => s('serviceTypeId');

  factory ShipmentDetail.fromJson(Map<String, dynamic> j) => ShipmentDetail(
    id: j['id'] as String,
    shipmentNumber: j['shipmentNumber'] as String? ?? '',
    trackingNumber: j['trackingNumber'] as String? ?? '',
    status: j['status'] as String? ?? '',
    items: jList(j['items']).map(ShipmentItem.fromJson).toList(),
    raw: j,
  );
}

/// One row of `/shipments/{id}/history` (append-only status log).
class StatusEvent {
  const StatusEvent({
    required this.status,
    required this.at,
    this.previousStatus,
    this.remarks,
    this.branchId,
    this.manifestId,
  });

  final String status;
  final DateTime at;
  final String? previousStatus;
  final String? remarks;
  final String? branchId;
  final String? manifestId;

  factory StatusEvent.fromJson(Map<String, dynamic> j) => StatusEvent(
    status: j['status'] as String? ?? '',
    at: jTime(j['changedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    previousStatus: jStr(j['previousStatus']),
    remarks: jStr(j['remarks']),
    branchId: jStr(j['branchId']),
    manifestId: jStr(j['manifestId']),
  );
}

/// A hub exception (hold, misroute, damaged...) raised against the shipment.
class ShipmentExceptionEvent {
  const ShipmentExceptionEvent({
    required this.type,
    required this.status,
    required this.raisedAt,
    this.hubBranchId,
    this.remarks,
    this.resolvedAt,
    this.resolution,
  });

  final String type;
  final String status;
  final DateTime raisedAt;
  final String? hubBranchId;
  final String? remarks;
  final DateTime? resolvedAt;
  final String? resolution;

  factory ShipmentExceptionEvent.fromJson(Map<String, dynamic> j) => ShipmentExceptionEvent(
    type: j['exceptionType'] as String? ?? '',
    status: j['status'] as String? ?? '',
    raisedAt: jTime(j['raisedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    hubBranchId: jStr(j['hubBranchId']),
    remarks: jStr(j['remarks']),
    resolvedAt: jTime(j['resolvedAt']),
    resolution: jStr(j['resolutionRemarks']),
  );
}

class ChargeLine {
  const ChargeLine(this.label, this.amount);

  final String label;
  final num amount;
}

/// Server charge breakup (preview `chargeBreakup` or a booked shipment's `/charges`).
class Charges {
  const Charges({required this.lines, this.netAmount});

  final List<ChargeLine> lines;
  final num? netAmount;

  static const _labels = {
    'freight': 'Freight',
    'fuelCharge': 'Fuel',
    'handlingCharge': 'Handling',
    'odaCharge': 'ODA',
    'insuranceCharge': 'Insurance',
    'otherCharges': 'Other charges',
    'appointmentDeliveryCharge': 'Appointment delivery',
    'doorDeliveryCharge': 'Door delivery',
    'toPayCharge': 'To-Pay charge',
    'gstAmount': 'GST',
    'discount': 'Discount',
    'discountAmount': 'Discount',
    'roundOff': 'Round off',
  };

  /// Keeps non-zero amounts only, in server order, plus named applicable charges.
  factory Charges.fromJson(Map<String, dynamic> j) {
    final lines = <ChargeLine>[];
    for (final e in _labels.entries) {
      final v = jNum(j[e.key]);
      if (v != null && v != 0) {
        lines.add(ChargeLine(e.value, e.key.startsWith('discount') ? -v.abs() : v));
      }
      if (e.key == 'insuranceCharge') {
        for (final a in jList(j['applicableChargeLines'])) {
          final amount = jNum(a['amount']);
          if (amount != null && amount != 0) lines.add(ChargeLine(jStr(a['chargeName']) ?? 'Charge', amount));
        }
      }
    }
    return Charges(lines: lines, netAmount: jNum(j['netAmount']));
  }
}

class DeliveryRun {
  const DeliveryRun({this.drsNumber, this.status, this.assignedAt, this.deliveredAt, this.receiverName, this.remarks});

  final String? drsNumber;
  final String? status;
  final DateTime? assignedAt;
  final DateTime? deliveredAt;
  final String? receiverName;
  final String? remarks;

  factory DeliveryRun.fromJson(Map<String, dynamic> j) => DeliveryRun(
    drsNumber: jStr(j['drsNumber']),
    status: jStr(j['status']),
    assignedAt: jTime(j['assignedAt']),
    deliveredAt: jTime(j['deliveredAt']),
    receiverName: jStr(j['receiverName']),
    remarks: jStr(j['deliveryRemarks']),
  );
}

class PodInfo {
  const PodInfo({
    this.photoUrl,
    this.signatureUrl,
    this.verificationStatus,
    this.entryStatus,
    this.deliveryDate,
    this.remark,
  });

  final String? photoUrl;
  final String? signatureUrl;
  final String? verificationStatus;
  final String? entryStatus;
  final DateTime? deliveryDate;
  final String? remark;

  factory PodInfo.fromJson(Map<String, dynamic> j) => PodInfo(
    photoUrl: jStr(j['photoUrl']),
    signatureUrl: jStr(j['signatureUrl']),
    verificationStatus: jStr(j['verificationStatus']),
    entryStatus: jStr(j['entryStatus']),
    deliveryDate: jTime(j['deliveryDate']),
    remark: jStr(j['remark']),
  );
}
