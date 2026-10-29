import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import 'wallet_models.dart';

/// `/api/v1/branch-wallet`. There is no wallet id anywhere: a caller gets their own
/// branch's wallet, a company admin passes `branchId` for another branch's.
class WalletRepository {
  WalletRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/v1/branch-wallet';

  Map<String, dynamic>? _branch(String? branchId) => branchId == null ? null : {'branchId': branchId};

  Future<Wallet> wallet(String? branchId) =>
      _api.get(_base, query: _branch(branchId), parse: (d) => Wallet.fromJson(jMap(d)));

  Future<WalletSummary> summary(String? branchId) =>
      _api.get('$_base/summary', query: _branch(branchId), parse: (d) => WalletSummary.fromJson(jMap(d)));

  Future<PageResponse<WalletTxn>> transactions({
    String? branchId,
    TxnFilter filter = const TxnFilter(),
    int page = 0,
    int size = 20,
  }) => _api.get(
    '$_base/transactions',
    query: {...?_branch(branchId), ...filter.query(), 'page': page, 'size': size, 'sort': 'createdAt,desc'},
    parse: (d) => PageResponse.fromJson(jMap(d), WalletTxn.fromJson),
  );

  Future<PageResponse<RechargeAttempt>> rechargeReport({
    String? status,
    String? mode,
    DateTime? from,
    DateTime? to,
    String? search,
    int page = 0,
    int size = 20,
  }) => _api.get(
    '$_base/recharge-report',
    query: {
      'status': ?status,
      'mode': ?mode,
      if (from != null) 'fromDate': Fmt.apiDate(from),
      if (to != null) 'toDate': Fmt.apiDate(to),
      if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      'page': page,
      'size': size,
      'sort': 'createdAt,desc',
    },
    parse: (d) => PageResponse.fromJson(jMap(d), RechargeAttempt.fromJson),
  );

  /// Asks the gateway now (same as the 2-minute scheduler); credits, fails or leaves it.
  Future<RechargeAttempt> checkAttempt(String id) =>
      _api.post('$_base/recharge-report/$id/check', body: const {}, parse: (d) => RechargeAttempt.fromJson(jMap(d)));

  /// Step one: the server fixes the amount at the gateway. Nothing is credited.
  Future<RechargeOrder> openRechargeOrder({String? branchId, required num amount, String? remarks}) => _api.post(
    '$_base/recharge/order',
    body: {'branchId': branchId, 'amount': amount, 'remarks': remarks},
    parse: (d) => RechargeOrder.fromJson(jMap(d)),
  );

  /// Step two: the server verifies the signature and credits what the gateway says was
  /// paid. Idempotent on `paymentReference`, so it is safe to retry.
  Future<WalletTxn> completeRecharge({
    String? branchId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) => _api.post(
    '$_base/recharge',
    body: {'branchId': branchId, 'gatewayOrderId': orderId, 'paymentReference': paymentId, 'signature': signature},
    parse: (d) => WalletTxn.fromJson(jMap(d)),
  );

  /// Company admin only.
  Future<WalletTxn> manual({
    required bool credit,
    required String branchId,
    required num amount,
    String? subType,
    String? referenceType,
    String? referenceId,
    String? remarks,
  }) => _api.post(
    '$_base/${credit ? 'credit' : 'debit'}',
    body: {
      'branchId': branchId,
      'amount': amount,
      'subTransactionType': subType,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'remarks': remarks,
    },
    parse: (d) => WalletTxn.fromJson(jMap(d)),
  );

  Future<String> uploadTopupProof(Uint8List bytes, String filename) => _api.post(
    '$_base/topup-requests/upload-proof',
    body: FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType('image', 'jpeg')),
    }),
    parse: (d) => jStr(jMap(d)['url']) ?? '',
  );

  Future<TopupRequest> createTopupRequest({
    String? branchId,
    required num amount,
    String? remarks,
    required String proofImageUrl,
  }) => _api.post(
    '$_base/topup-requests',
    body: {'branchId': branchId, 'amount': amount, 'remarks': remarks, 'proofImageUrl': proofImageUrl},
    parse: (d) => TopupRequest.fromJson(jMap(d)),
  );

  Future<PageResponse<TopupRequest>> topupRequests({String? branchId, String? status, int page = 0, int size = 50}) =>
      _api.get(
        '$_base/topup-requests',
        query: {...?_branch(branchId), 'status': ?status, 'page': page, 'size': size, 'sort': 'createdAt,desc'},
        parse: (d) => PageResponse.fromJson(jMap(d), TopupRequest.fromJson),
      );

  Future<TopupRequest> decideTopup(String id, {required bool approve, String? remarks}) => _api.patch(
    '$_base/topup-requests/$id/${approve ? 'approve' : 'reject'}',
    body: {'remarks': remarks},
    parse: (d) => TopupRequest.fromJson(jMap(d)),
  );
}

final walletRepositoryProvider = Provider((ref) => WalletRepository(ref.watch(apiClientProvider)));
