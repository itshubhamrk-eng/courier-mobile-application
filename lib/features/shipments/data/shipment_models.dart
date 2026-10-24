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
  const Charges({required this.lines, this.adjustments = const [], this.netAmount});

  /// Charge lines (freight, fuel, handling, ODA, FOV, applicable and extra charges).
  final List<ChargeLine> lines;

  /// GST, discount and round off, shown after the charge lines like on a bill.
  final List<ChargeLine> adjustments;
  final num? netAmount;

  static const _chargeLabels = {
    'freight': 'Freight',
    'fuelCharge': 'Fuel',
    'handlingCharge': 'Handling',
    'odaCharge': 'ODA',
    'insuranceCharge': 'Insurance / FOV',
    'otherCharges': 'Other charges',
    'appointmentDeliveryCharge': 'Appointment delivery',
    'doorDeliveryCharge': 'Door delivery',
    'toPayCharge': 'To-Pay charge',
  };

  static const _adjustmentLabels = {
    'discount': 'Discount',
    'discountAmount': 'Discount',
    'gstAmount': 'GST',
    'roundOff': 'Round off',
  };

  /// Keeps non-zero amounts only, in server order, plus named applicable charges.
  factory Charges.fromJson(Map<String, dynamic> j) {
    final lines = <ChargeLine>[];
    for (final e in _chargeLabels.entries) {
      final v = jNum(j[e.key]);
      if (v != null && v != 0) lines.add(ChargeLine(e.value, v));
      if (e.key == 'insuranceCharge') {
        for (final a in jList(j['applicableChargeLines'])) {
          final amount = jNum(a['amount']);
          if (amount != null && amount != 0) lines.add(ChargeLine(jStr(a['chargeName']) ?? 'Charge', amount));
        }
      }
    }
    final adjustments = <ChargeLine>[];
    for (final e in _adjustmentLabels.entries) {
      final v = jNum(j[e.key]);
      if (v != null && v != 0) adjustments.add(ChargeLine(e.value, e.key.startsWith('discount') ? -v.abs() : v));
    }
    return Charges(lines: lines, adjustments: adjustments, netAmount: jNum(j['netAmount']));
  }
}

class DeliveryRun {
  const DeliveryRun({
    this.drsNumber,
    this.status,
    this.assignedAt,
    this.deliveredAt,
    this.receiverName,
    this.remarks,
    this.deliveryUserId,
    this.deliveryBranchId,
  });

  /// With [assignedAt], identifies the run for `/shipment-movement/drs/detail`.
  final String? deliveryUserId;
  final String? deliveryBranchId;

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
    deliveryUserId: jStr(j['deliveryUserId']),
    deliveryBranchId: jStr(j['deliveryBranchId']),
  );
}

/// A file on the shipment: uploaded document (`/shipments/{id}/documents`),
/// the E-Way Bill document or the shipment photo.
class ShipmentFile {
  const ShipmentFile({required this.label, required this.url, this.type, this.remarks, this.addedAt});

  final String label;
  final String url;

  /// Server document type (INVOICE, EWAY_BILL, PACKING_LIST, LR_COPY, POD, ...), or PHOTO.
  final String? type;
  final String? remarks;
  final DateTime? addedAt;

  bool get isImage => RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false).hasMatch(Uri.tryParse(url)?.path ?? url);

  factory ShipmentFile.fromDocumentJson(Map<String, dynamic> j) {
    final type = jStr(j['documentType']);
    return ShipmentFile(
      label: jStr(j['documentName']) ?? _typeLabel(type),
      url: j['documentUrl'] as String? ?? '',
      type: type,
      remarks: jStr(j['remarks']),
      addedAt: jTime(j['createdDate']),
    );
  }

  static String _typeLabel(String? type) => switch (type) {
    'INVOICE' => 'Invoice',
    'EWAY_BILL' => 'E-Way Bill',
    'PACKING_LIST' => 'Packing list',
    'LR_COPY' => 'LR copy',
    'POD' => 'Proof of delivery',
    _ => 'Document',
  };
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

/// Why a delivery attempt failed (`DeliveryFailureReason`). [other] needs remarks.
enum FailureReason {
  customerRefused('CUSTOMER_REFUSED', 'Customer refused'),
  addressNotFound('ADDRESS_NOT_FOUND', 'Address not found'),
  customerUnavailable('CUSTOMER_UNAVAILABLE', 'Customer not available'),
  rescheduleRequested('RESCHEDULE_REQUESTED', 'Customer asked to reschedule'),
  paymentNotReady('PAYMENT_NOT_READY', 'Payment not ready'),
  other('OTHER', 'Other');

  const FailureReason(this.code, this.label);

  final String code;
  final String label;

  static String labelOf(String? code) =>
      values.where((r) => r.code == code).firstOrNull?.label ?? (code ?? 'Unknown reason');
}

/// One failed delivery attempt (`DeliveryAttemptResponse`).
class DeliveryAttempt {
  const DeliveryAttempt({
    required this.attemptNo,
    required this.maxAttempts,
    this.reason,
    this.remarks,
    this.outcome,
    this.drsNumber,
    this.attemptedAt,
  });

  final int attemptNo;
  final int maxAttempts;
  final String? reason;
  final String? remarks;

  /// RETRY: back at the branch for the next DRS. RTO: shipment RETURNED.
  final String? outcome;
  final String? drsNumber;
  final DateTime? attemptedAt;

  bool get returnedToOrigin => outcome == 'RTO';
  String get reasonLabel => FailureReason.labelOf(reason);

  factory DeliveryAttempt.fromJson(Map<String, dynamic> j) => DeliveryAttempt(
    attemptNo: jInt(j['attemptNo']) ?? 0,
    maxAttempts: jInt(j['maxAttempts']) ?? 0,
    reason: jStr(j['reason']),
    remarks: jStr(j['remarks']),
    outcome: jStr(j['outcome']),
    drsNumber: jStr(j['drsNumber']),
    attemptedAt: jTime(j['attemptedAt']),
  );
}
