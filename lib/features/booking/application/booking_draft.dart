import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../auth/application/auth_controller.dart';

class ItemDraft {
  const ItemDraft({
    this.name = 'Package',
    this.quantity = 1,
    this.weight,
    this.length,
    this.width,
    this.height,
    this.declaredValue,
  });

  final String name;
  final int quantity;

  /// Total actual weight of this row in kg (all pieces), as the server reads it.
  final num? weight;
  final num? length;
  final num? width;
  final num? height;
  final num? declaredValue;

  bool get hasDimensions => length != null && width != null && height != null;

  Map<String, dynamic> toJson() => {
    'itemName': name.trim().isEmpty ? 'Package' : name.trim(),
    'quantity': quantity,
    'weight': weight,
    'lengthCm': length,
    'widthCm': width,
    'heightCm': height,
    'declaredValue': declaredValue,
    'fragile': false,
    'dangerousGoods': false,
  };
}

/// Everything typed into the booking form. Kept in a provider so leaving the
/// screen does not lose it; cleared after a successful booking.
class BookingDraft {
  const BookingDraft({
    this.businessCustomerId,
    this.businessCustomerName,
    this.senderName = '',
    this.senderContact = '',
    this.senderAddress = '',
    this.receiverName = '',
    this.receiverContact = '',
    this.receiverAddress = '',
    this.pickupPincode = '',
    this.deliveryPincode = '',
    this.destinationAreaId,
    this.destinationAreaLabel,
    this.deliveryType = 'DOOR',
    this.items = const [ItemDraft()],
    this.numberOfPackages,
    this.invoiceValue,
    this.ewayInvoiceNumber = '',
    this.ewayInvoiceDate,
    this.ewayConsignorGstin = '',
    this.ewayConsigneeGstin = '',
    this.serviceTypeId,
    this.paymentModeId,
    this.remarks = '',
  });

  final String? businessCustomerId;
  final String? businessCustomerName;
  final String senderName;
  final String senderContact;
  final String senderAddress;
  final String receiverName;
  final String receiverContact;
  final String receiverAddress;
  final String pickupPincode;
  final String deliveryPincode;
  final String? destinationAreaId;
  final String? destinationAreaLabel;
  final String deliveryType;
  final List<ItemDraft> items;

  /// Box / carton count; defaults to the item quantity total.
  final int? numberOfPackages;
  final num? invoiceValue;
  final String ewayInvoiceNumber;
  final DateTime? ewayInvoiceDate;
  final String ewayConsignorGstin;
  final String ewayConsigneeGstin;
  final String? serviceTypeId;
  final String? paymentModeId;
  final String remarks;

  int get totalQuantity => items.fold(0, (s, i) => s + i.quantity);
  int get packageCount => numberOfPackages ?? totalQuantity;
  num get totalActualWeight => items.fold<num>(0, (s, i) => s + (i.weight ?? 0));
  num? get declaredValue {
    final values = items.map((i) => i.declaredValue).nonNulls;
    return values.isEmpty ? null : values.fold<num>(0, (s, v) => s + v);
  }

  bool ewayBillNeeded(num? threshold) => threshold != null && (invoiceValue ?? 0) >= threshold;

  /// Chargeable weight to feed the two preview endpoints, using the server's
  /// own rule (`ShipmentServiceImpl.summariseWeight`): per-item volumetric
  /// L×W×H/5000 × quantity, max(actual, volumetric, company minimum), 3 dp.
  /// Only a preview input; the server recomputes it on booking.
  num previewChargeableWeight(num? minimumKg) {
    double r3(double v) => (v * 1000).roundToDouble() / 1000;
    final actual = r3(totalActualWeight.toDouble());
    var volumetric = 0.0;
    for (final i in items) {
      if (i.hasDimensions) volumetric += r3(i.length! * i.width! * i.height! / 5000) * i.quantity;
    }
    volumetric = r3(volumetric);
    var chargeable = actual > volumetric ? actual : volumetric;
    if (minimumKg != null && minimumKg > chargeable) chargeable = minimumKg.toDouble();
    return chargeable;
  }

  Map<String, dynamic> toCreateRequest(String branchId) {
    String? t(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      'bookingBranchId': branchId,
      'pickupPincode': pickupPincode.trim(),
      'deliveryPincode': deliveryPincode.trim(),
      'destinationAreaId': destinationAreaId,
      'senderName': senderName.trim(),
      'senderContact': senderContact.trim(),
      'senderAddress': senderAddress.trim(),
      'receiverName': receiverName.trim(),
      'receiverContact': receiverContact.trim(),
      'receiverAddress': receiverAddress.trim(),
      'serviceTypeId': serviceTypeId,
      'paymentModeId': paymentModeId,
      'deliveryType': deliveryType,
      'numberOfPackages': packageCount,
      'declaredValue': declaredValue,
      'invoiceValue': invoiceValue,
      'items': items.map((i) => i.toJson()).toList(),
      'businessCustomerId': businessCustomerId,
      'remarks': t(remarks),
      if (t(ewayInvoiceNumber) != null)
        'ewayBill': {
          'invoiceNumber': ewayInvoiceNumber.trim(),
          'invoiceDate': Fmt.apiDate(ewayInvoiceDate ?? DateTime.now()),
          'documentType': 'INVOICE',
          'consignorGstin': t(ewayConsignorGstin),
          'consigneeGstin': t(ewayConsigneeGstin),
        },
    };
  }

  BookingDraft copyWith({
    Object? businessCustomerId = _keep,
    Object? businessCustomerName = _keep,
    String? senderName,
    String? senderContact,
    String? senderAddress,
    String? receiverName,
    String? receiverContact,
    String? receiverAddress,
    String? pickupPincode,
    String? deliveryPincode,
    Object? destinationAreaId = _keep,
    Object? destinationAreaLabel = _keep,
    String? deliveryType,
    List<ItemDraft>? items,
    Object? numberOfPackages = _keep,
    Object? invoiceValue = _keep,
    String? ewayInvoiceNumber,
    Object? ewayInvoiceDate = _keep,
    String? ewayConsignorGstin,
    String? ewayConsigneeGstin,
    Object? serviceTypeId = _keep,
    Object? paymentModeId = _keep,
    String? remarks,
  }) => BookingDraft(
    businessCustomerId: businessCustomerId == _keep ? this.businessCustomerId : businessCustomerId as String?,
    businessCustomerName: businessCustomerName == _keep ? this.businessCustomerName : businessCustomerName as String?,
    senderName: senderName ?? this.senderName,
    senderContact: senderContact ?? this.senderContact,
    senderAddress: senderAddress ?? this.senderAddress,
    receiverName: receiverName ?? this.receiverName,
    receiverContact: receiverContact ?? this.receiverContact,
    receiverAddress: receiverAddress ?? this.receiverAddress,
    pickupPincode: pickupPincode ?? this.pickupPincode,
    deliveryPincode: deliveryPincode ?? this.deliveryPincode,
    destinationAreaId: destinationAreaId == _keep ? this.destinationAreaId : destinationAreaId as String?,
    destinationAreaLabel: destinationAreaLabel == _keep ? this.destinationAreaLabel : destinationAreaLabel as String?,
    deliveryType: deliveryType ?? this.deliveryType,
    items: items ?? this.items,
    numberOfPackages: numberOfPackages == _keep ? this.numberOfPackages : numberOfPackages as int?,
    invoiceValue: invoiceValue == _keep ? this.invoiceValue : invoiceValue as num?,
    ewayInvoiceNumber: ewayInvoiceNumber ?? this.ewayInvoiceNumber,
    ewayInvoiceDate: ewayInvoiceDate == _keep ? this.ewayInvoiceDate : ewayInvoiceDate as DateTime?,
    ewayConsignorGstin: ewayConsignorGstin ?? this.ewayConsignorGstin,
    ewayConsigneeGstin: ewayConsigneeGstin ?? this.ewayConsigneeGstin,
    serviceTypeId: serviceTypeId == _keep ? this.serviceTypeId : serviceTypeId as String?,
    paymentModeId: paymentModeId == _keep ? this.paymentModeId : paymentModeId as String?,
    remarks: remarks ?? this.remarks,
  );

  static const _keep = Object();
}

final bookingDraftProvider = NotifierProvider<BookingDraftController, BookingDraft>(BookingDraftController.new);

class BookingDraftController extends Notifier<BookingDraft> {
  @override
  BookingDraft build() {
    // A different user signing in starts with an empty form.
    ref.watch(sessionProvider.select((s) => s?.userId));
    return const BookingDraft();
  }

  void update(BookingDraft Function(BookingDraft d) change) => state = change(state);

  void reset() => state = const BookingDraft();
}
