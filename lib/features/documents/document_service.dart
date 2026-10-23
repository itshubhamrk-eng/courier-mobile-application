import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../auth/application/auth_controller.dart';
import '../drs/data/drs_repository.dart';
import '../loading_sheet/data/loading_sheet_repository.dart';
import '../masters/data/masters.dart';
import '../pod/data/pod_repository.dart';
import '../shipments/data/shipment_models.dart';
import '../shipments/data/shipment_repository.dart';
import '../thc/data/thc_repository.dart';
import 'pdf_documents.dart';

final documentServiceProvider = Provider<DocumentService>((ref) => DocumentService(ref));

/// Gathers server data for a document and lays it out as PDF.
class DocumentService {
  DocumentService(this._ref);

  final Ref _ref;
  pw.ThemeData? _theme;

  Future<pw.ThemeData> _pdfTheme() async => _theme ??= pdfTheme(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );

  String get _user => _ref.read(sessionProvider)?.displayName ?? 'Branch Operations';

  Future<Letterhead> _letterhead() async {
    final fallback = Letterhead(name: _ref.read(sessionProvider)?.companyName ?? 'Courier');
    try {
      return await _ref
          .read(apiClientProvider)
          .get(
            '/api/v1/company-profile',
            parse: (d) {
              final j = jMap(d);
              final address = [
                j['addressLine1'],
                j['addressLine2'],
                j['city'],
                j['state'],
                j['postalCode'],
              ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
              return Letterhead(
                name: jStr(j['companyName']) ?? fallback.name,
                address: address.isEmpty ? null : address,
                gstNumber: jStr(j['gstNumber']),
                mobile: jStr(j['mobile']),
              );
            },
          );
    } on ApiException {
      return fallback;
    }
  }

  Future<Map<String, Branch>> _branches() =>
      _ref.read(branchNamesProvider.future).catchError((_) => <String, Branch>{});

  Future<List<Option>> _paymentModes() => _ref.read(paymentModesProvider.future).catchError((_) => <Option>[]);

  Future<List<T>> _orEmpty<T>(Future<List<T>> f) async {
    try {
      return await f;
    } on ApiException {
      return <T>[];
    }
  }

  /// To-Pay freight (collected at delivery, not cash-on-delivery), as on the web THC.
  static num? _toPay(String? modeId, num? net, List<Option> modes) {
    final m = modes.where((x) => x.id == modeId).firstOrNull;
    return m != null && m.flags['collectAtDelivery'] == true && m.flags['cashOnDelivery'] != true ? net : null;
  }

  static num? _collect(String? modeId, num? net, List<Option> modes) {
    final m = modes.where((x) => x.id == modeId).firstOrNull;
    return m != null && (m.flags['collectAtDelivery'] == true || m.flags['cashOnDelivery'] == true) ? net : null;
  }

  Future<Uint8List> label(String shipmentId) async {
    final s = await _ref.read(shipmentRepositoryProvider).byId(shipmentId);
    final branches = await _branches();
    final modes = await _paymentModes();
    final services = await _ref.read(serviceTypesProvider.future).catchError((_) => <Option>[]);
    return buildLabels(
      LabelData(
        companyName: _ref.read(sessionProvider)?.companyName ?? 'Courier',
        trackingNumber: s.trackingNumber,
        shipmentNumber: s.shipmentNumber,
        packages: s.n('numberOfPackages')?.toInt() ?? 1,
        bookingDate: s.t('bookingDate'),
        fromLabel: branches[s.bookingBranchId]?.label ?? s.s('fromCity'),
        toLabel: s.s('toCity'),
        toPincode: s.s('deliveryPincode'),
        senderName: s.s('senderName'),
        receiverName: s.s('receiverName'),
        receiverContact: s.s('receiverContact'),
        receiverAddress: s.s('receiverAddress'),
        weight: s.n('chargeableWeight'),
        paymentMode: modes.where((m) => m.id == s.paymentModeId).firstOrNull?.name,
        serviceType: services.where((m) => m.id == s.serviceTypeId).firstOrNull?.name,
      ),
      await _pdfTheme(),
    );
  }

  /// Loading sheet, or its THC once dispatched ([asThc]).
  Future<Uint8List> sheet(String manifestId, {required bool asThc}) async {
    final repo = _ref.read(loadingSheetRepositoryProvider);
    final results = await Future.wait<Object>([
      repo.byId(manifestId),
      repo.shipmentsOf(manifestId),
      _branches(),
      _paymentModes(),
      _letterhead(),
      if (asThc) _ref.read(thcRepositoryProvider).sheetAsThc(manifestId),
      if (asThc) _orEmpty(_ref.read(thcRepositoryProvider).vehicles()),
      if (asThc) _orEmpty(_ref.read(thcRepositoryProvider).activeUsers()),
    ]);
    final sheet = results[0] as LoadingSheet;
    final shipments = results[1] as List<ShipmentSummary>;
    final branches = results[2] as Map<String, Branch>;
    final modes = results[3] as List<Option>;
    final thc = asThc ? results[5] as ThcResult : null;
    final vehicle = asThc ? (results[6] as List<Vehicle>).where((v) => v.id == thc!.vehicleId).firstOrNull : null;
    final driver = asThc ? (results[7] as List<StaffUser>).where((u) => u.id == thc!.driverUserId).firstOrNull : null;

    return buildSheet(
      theme: await _pdfTheme(),
      letterhead: results[4] as Letterhead,
      isThc: asThc,
      number: sheet.number,
      fromLabel: branches[sheet.bookingBranchId]?.label ?? '—',
      toLabel: branches[sheet.deliveryBranchId]?.label ?? '—',
      createdAt: sheet.createdAt,
      dispatchedAt: thc?.dispatchedAt,
      vehicle: vehicle?.number,
      driver: driver == null ? null : [driver.name, driver.mobile].nonNulls.join(' · '),
      expenses: thc == null
          ? const {}
          : {
              'Fuel': thc.fuelCost,
              'Driver advance': thc.driverAdvance,
              'Toll': thc.tollAmount,
              'Other': thc.otherAmount,
            },
      generatedBy: _user,
      rows: [
        for (final s in shipments)
          SheetRow(
            shipmentNumber: s.shipmentNumber,
            trackingNumber: s.trackingNumber,
            consignor: s.senderName,
            consignee: s.receiverName,
            fromCity: s.fromCity,
            toCity: s.toCity,
            bookingDate: s.bookingDate,
            packages: s.packages,
            weight: s.chargeableWeight,
            toPayAmount: _toPay(s.paymentModeId, s.netAmount, modes),
          ),
      ],
    );
  }

  Future<Uint8List> drs(DrsRun run) async {
    final results = await Future.wait<Object>([
      _ref.read(drsRepositoryProvider).runDetail(run),
      _branches(),
      _paymentModes(),
      _letterhead(),
      _orEmpty(_ref.read(thcRepositoryProvider).activeUsers()),
    ]);
    final detail = results[0] as ({String? drsNumber, List<DrsRow> rows});
    final modes = results[2] as List<Option>;
    final partner = (results[4] as List<StaffUser>).where((u) => u.id == run.deliveryUserId).firstOrNull;
    return buildDrs(
      theme: await _pdfTheme(),
      letterhead: results[3] as Letterhead,
      number: detail.drsNumber ?? run.drsNumber ?? 'DRS',
      branchLabel: (results[1] as Map<String, Branch>)[run.deliveryBranchId]?.label ?? '—',
      partner: partner == null ? '—' : [partner.name, partner.mobile].nonNulls.join(' · '),
      runDate: run.runDate,
      generatedBy: _user,
      rows: [
        for (final r in detail.rows)
          DrsDocRow(
            shipmentNumber: r.shipmentNumber ?? '',
            trackingNumber: r.trackingNumber,
            receiver: r.receiverName,
            contact: r.receiverContact,
            address: r.receiverAddress,
            payment: modes.where((m) => m.id == r.paymentModeId).firstOrNull?.name,
            collectAmount: _collect(r.paymentModeId, r.netAmount, modes),
          ),
      ],
    );
  }

  Future<Uint8List> pod(String shipmentId) async {
    final shipments = _ref.read(shipmentRepositoryProvider);
    final s = await shipments.byId(shipmentId);
    final pod = await _ref.read(podRepositoryProvider).latest(shipmentId).catchError((_) => null);
    DeliveryRun? run;
    try {
      run = await shipments.deliveryRun(shipmentId);
    } on ApiException {
      run = null;
    }
    return buildPod(
      theme: await _pdfTheme(),
      letterhead: await _letterhead(),
      trackingNumber: s.trackingNumber,
      shipmentNumber: s.shipmentNumber,
      status: s.status,
      receiverName: run?.receiverName ?? s.s('receiverName'),
      receiverAddress: s.s('receiverAddress'),
      deliveredAt: s.t('deliveredAt') ?? run?.deliveredAt,
      podStatus: pod?.status,
      drsNumber: run?.drsNumber,
      photo: await _bytes(pod?.photoUrl ?? s.s('podPhotoUrl')),
      signature: await _bytes(pod?.signatureUrl ?? s.s('podSignatureUrl')),
      generatedBy: _user,
    );
  }

  /// Downloads a POD image with the user's session; null when it cannot be read.
  Future<Uint8List?> _bytes(String? url) async {
    if (url == null) return null;
    try {
      final res = await _ref.read(dioProvider).get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      return res.data == null ? null : Uint8List.fromList(res.data!);
    } on DioException {
      return null;
    }
  }
}
