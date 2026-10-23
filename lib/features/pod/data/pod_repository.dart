import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../shipments/data/shipment_models.dart';

/// Server POD verification (`PodVerificationResponse`). Every upload by a
/// branch starts PENDING (company review); PASS = approved, FAIL = rejected.
class PodVerification {
  const PodVerification({
    required this.id,
    required this.status,
    this.score,
    this.reasons = const [],
    this.photoUrl,
    this.signatureUrl,
    this.verifiedAt,
    this.reviewRemarks,
  });

  final String id;
  final String status;
  final int? score;
  final List<String> reasons;
  final String? photoUrl;
  final String? signatureUrl;
  final DateTime? verifiedAt;
  final String? reviewRemarks;

  /// A rejected POD must be uploaded again before the delivery can be closed.
  bool get usable => status == 'PENDING' || status == 'PASS';

  factory PodVerification.fromJson(Map<String, dynamic> j) => PodVerification(
    id: j['id'] as String,
    status: j['verificationStatus'] as String? ?? '',
    score: jInt(j['verificationScore']),
    reasons: (j['verificationReasons'] as List?)?.whereType<String>().toList() ?? const [],
    photoUrl: jStr(j['photoUrl']),
    signatureUrl: jStr(j['signatureUrl']),
    verifiedAt: jTime(j['verifiedAt']),
    reviewRemarks: jStr(j['reviewRemarks']),
  );
}

final podRepositoryProvider = Provider<PodRepository>((ref) => PodRepository(ref.watch(apiClientProvider)));

class PodRepository {
  PodRepository(this._api);

  final ApiClient _api;

  /// Latest POD on file for the shipment, or null when none was uploaded.
  Future<PodVerification?> latest(String shipmentId) async {
    try {
      return await _api.get(
        '/api/v1/shipments/$shipmentId/pod/verification',
        parse: (d) => d == null ? null : PodVerification.fromJson(jMap(d)),
      );
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.notFound) return null;
      rethrow;
    }
  }

  /// Uploads photo (+ optional signature). Creates a new POD record on the
  /// server each call, so callers check [latest] first after any lost answer.
  Future<PodVerification> upload({
    required ShipmentDetail shipment,
    required Uint8List photo,
    Uint8List? signature,
    required String receiverName,
    String? qrScanValue,
    void Function(double progress)? onProgress,
  }) {
    final form = FormData.fromMap({
      'photo': MultipartFile.fromBytes(
        photo,
        filename: 'pod-${shipment.trackingNumber}.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
      if (signature != null)
        'signature': MultipartFile.fromBytes(
          signature,
          filename: 'signature-${shipment.trackingNumber}.png',
          contentType: DioMediaType('image', 'png'),
        ),
      'receiverName': receiverName,
      'awbNumber': shipment.trackingNumber,
      'shipmentNumber': shipment.shipmentNumber,
      'deliveryDateTime': DateTime.now().toUtc().toIso8601String(),
      'qrScanValue': ?qrScanValue,
    });
    return _api.post(
      '/api/v1/shipments/${shipment.id}/pod/verify',
      body: form,
      onSendProgress: onProgress == null ? null : (sent, total) => total > 0 ? onProgress(sent / total) : null,
      parse: (d) => PodVerification.fromJson(jMap(d)),
    );
  }

  /// Closes the delivery. Only this call changes the shipment's status; the
  /// server checks it is OUT_FOR_DELIVERY and on a DRS.
  Future<ShipmentDetail> deliver({required String shipmentId, required String receiverName, String? remarks}) =>
      _api.post(
        '/api/v1/shipment-movement/deliver',
        body: {
          'shipmentId': shipmentId,
          'receiverName': receiverName,
          'remarks': (remarks == null || remarks.trim().isEmpty) ? null : remarks.trim(),
          // POD files are already stored by the verify upload, as on the web delivery page.
          'otp': null,
          'signatureUrl': null,
          'photoUrl': null,
        },
        parse: (d) => ShipmentDetail.fromJson(jMap(d)),
      );
}
