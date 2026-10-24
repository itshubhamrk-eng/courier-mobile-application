import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';

class Branch {
  const Branch({
    required this.id,
    required this.code,
    required this.name,
    this.city,
    this.postalCode,
    this.type,
    this.assignedHubId,
  });

  final String id;
  final String code;
  final String name;
  final String? city;
  final String? postalCode;
  final String? type;

  /// The hub this branch normally sends to.
  final String? assignedHubId;

  bool get isHub => type == 'HUB';

  String get label => city == null ? name : '$name, $city';

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
    id: j['id'] as String,
    code: j['branchCode'] as String? ?? '',
    name: j['branchName'] as String? ?? '',
    city: jStr(j['city']),
    postalCode: jStr(j['postalCode']),
    type: jStr(j['branchType']),
    assignedHubId: jStr(j['assignedHubId']),
  );
}

class Option {
  const Option({required this.id, required this.code, required this.name, this.flags = const {}});

  final String id;
  final String code;
  final String name;

  /// Extra booleans from the master row (e.g. `cashOnDelivery`, `collectAtDelivery`).
  final Map<String, bool> flags;

  String get label => '$name ($code)';

  factory Option.fromJson(Map<String, dynamic> j, {List<String> flagKeys = const []}) => Option(
    id: j['id'] as String,
    code: j['code'] as String? ?? '',
    name: j['name'] as String? ?? '',
    flags: {for (final k in flagKeys) k: j[k] == true},
  );
}

class PincodeArea {
  const PincodeArea({required this.areaId, required this.label, required this.primary, required this.oda});

  final String areaId;
  final String label;
  final bool primary;
  final bool oda;

  factory PincodeArea.fromJson(Map<String, dynamic> j) {
    final area = jStr(j['areaName']);
    final city = jStr(j['cityName']);
    return PincodeArea(
      areaId: j['areaId'] as String,
      label: area == null ? (j['areaId'] as String) : (city == null ? area : '$area, $city'),
      primary: j['primary'] == true,
      oda: j['odaApplicable'] == true,
    );
  }
}

/// The company settings the booking screen needs.
class BookingSettings {
  const BookingSettings({this.minimumChargeableKg, this.ewayBillThreshold, this.defaultAppointmentCharge});

  final num? minimumChargeableKg;
  final num? ewayBillThreshold;

  /// Prefilled when appointment delivery is turned on, as on the web form.
  final num? defaultAppointmentCharge;

  factory BookingSettings.fromJson(Map<String, dynamic> j) => BookingSettings(
    minimumChargeableKg: jNum(jMap(j['shipment'])['defaultChargeableWeightKg']),
    ewayBillThreshold: jNum(jMap(j['ewayBill'])['ewayBillMandatoryValue']),
    defaultAppointmentCharge: jNum(jMap(j['shipment'])['defaultAppointmentDeliveryCharge']),
  );
}

final mastersRepositoryProvider = Provider<MastersRepository>((ref) => MastersRepository(ref.watch(apiClientProvider)));

/// Cached for the session: masters change rarely; pull to refresh invalidates.
final branchDirectoryProvider = FutureProvider<List<Branch>>((ref) => ref.watch(mastersRepositoryProvider).branches());

final branchNamesProvider = FutureProvider<Map<String, Branch>>((ref) async {
  final list = await ref.watch(branchDirectoryProvider.future);
  return {for (final b in list) b.id: b};
});

final serviceTypesProvider = FutureProvider<List<Option>>((ref) => ref.watch(mastersRepositoryProvider).serviceTypes());

final paymentModesProvider = FutureProvider<List<Option>>((ref) => ref.watch(mastersRepositoryProvider).paymentModes());

final bookingSettingsProvider = FutureProvider<BookingSettings>(
  (ref) => ref.watch(mastersRepositoryProvider).bookingSettings(),
);

class MastersRepository {
  MastersRepository(this._api);

  final ApiClient _api;

  Future<List<Branch>> branches() =>
      _api.get('/api/v1/branches/directory', parse: (d) => PageResponse.fromJson(jMap(d), Branch.fromJson).content);

  Future<List<Option>> serviceTypes() => _api.get(
    '/api/v1/master/service-types',
    query: {'status': 'ACTIVE', 'size': 100, 'sort': 'displayOrder,asc'},
    parse: (d) => PageResponse.fromJson(jMap(d), Option.fromJson).content,
  );

  Future<List<Option>> paymentModes() => _api.get(
    '/api/v1/master/payment-modes',
    query: {'status': 'ACTIVE', 'size': 100, 'sort': 'displayOrder,asc'},
    parse: (d) => PageResponse.fromJson(
      jMap(d),
      (j) => Option.fromJson(j, flagKeys: const ['cashOnDelivery', 'collectAtDelivery', 'collectAtBooking']),
    ).content,
  );

  Future<BookingSettings> bookingSettings() =>
      _api.get('/api/v1/company-settings', parse: (d) => BookingSettings.fromJson(jMap(d)));

  /// Areas of a 6-digit pincode; empty when the pincode is not in the master.
  Future<List<PincodeArea>> pincodeAreas(String pincode) async {
    final id = await _api.get(
      '/api/v1/global-masters/pincodes',
      query: {'search': pincode, 'size': 5},
      parse: (d) =>
          jList(jMap(d)['content']).where((r) => r['code'] == pincode).map((r) => r['id'] as String).firstOrNull,
    );
    if (id == null) return const [];
    return _api.get(
      '/api/v1/global-masters/pincodes/$id/areas',
      parse: (d) => jList(d).map(PincodeArea.fromJson).toList(),
    );
  }
}
