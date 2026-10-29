import '../../../core/format.dart';

/// Branch wallet shapes, one-to-one with courier-service `/api/v1/branch-wallet`
/// (same as the web app's `wallet.model.ts`). Money is in rupees except
/// [RechargeOrder.amountMinor], which is the gateway's paise contract.

/// Why a ledger entry happened: the backend's three-letter code.
const subTypeLabels = {
  'WRC': 'Wallet Recharge',
  'SBK': 'Shipment Booking',
  'SRF': 'Shipment Refund',
  'COD': 'COD Settlement',
  'COM': 'Commission',
  'BST': 'Branch Settlement',
  'MCR': 'Manual Credit',
  'MDB': 'Manual Debit',
  'TRI': 'Transfer In',
  'TRO': 'Transfer Out',
  'ADJ': 'Adjustment',
  'PNL': 'Penalty',
};

/// Reasons allowed on a credit / debit (backend `SubTransactionType.creditable()` / `debitable()`).
const creditSubTypes = ['WRC', 'SRF', 'COD', 'COM', 'BST', 'MCR', 'TRI', 'ADJ'];
const debitSubTypes = ['SBK', 'COD', 'COM', 'BST', 'MDB', 'TRO', 'ADJ', 'PNL'];
const referenceTypes = ['PAYMENT', 'SHIPMENT', 'SETTLEMENT', 'SYSTEM', 'MANUAL'];

String subTypeLabel(String? code) => code == null ? '–' : (subTypeLabels[code] ?? prettyToken(code));

/// BOOKING_CHARGE -> Booking Charge.
String prettyToken(String? v) => (v ?? '')
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

class Wallet {
  const Wallet({
    required this.id,
    required this.walletNumber,
    required this.branchId,
    required this.status,
    required this.available,
    required this.hold,
    required this.total,
    required this.currency,
    this.branchCode,
    this.branchName,
  });

  final String id;
  final String walletNumber;
  final String branchId;
  final String? branchCode;
  final String? branchName;
  final String status;
  final num available;
  final num hold;
  final num total;
  final String currency;

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
    id: jStr(j['id']) ?? '',
    walletNumber: jStr(j['walletNumber']) ?? '–',
    branchId: jStr(j['branchId']) ?? '',
    branchCode: jStr(j['branchCode']),
    branchName: jStr(j['branchName']),
    status: jStr(j['status']) ?? 'ACTIVE',
    available: jNum(j['availableBalance']) ?? 0,
    hold: jNum(j['holdBalance']) ?? 0,
    total: jNum(j['totalBalance']) ?? 0,
    currency: jStr(j['currency']) ?? 'INR',
  );
}

/// `GET /branch-wallet/summary`: balances plus settled period figures, all server-computed.
class WalletSummary {
  const WalletSummary({
    required this.walletNumber,
    required this.branchId,
    required this.status,
    required this.available,
    required this.hold,
    required this.total,
    required this.todayCredit,
    required this.todayDebit,
    required this.monthCredit,
    required this.monthDebit,
    required this.todayCreditCommission,
    required this.bookingPendingCommission,
    required this.deliveryPendingCommission,
    this.branchCode,
    this.branchName,
    this.lastRechargeAmount,
    this.lastRechargeAt,
  });

  final String walletNumber;
  final String branchId;
  final String? branchCode;
  final String? branchName;
  final String status;
  final num available;
  final num hold;
  final num total;
  final num todayCredit;
  final num todayDebit;
  final num monthCredit;
  final num monthDebit;
  final num todayCreditCommission;
  final num bookingPendingCommission;
  final num deliveryPendingCommission;
  final num? lastRechargeAmount;
  final DateTime? lastRechargeAt;

  factory WalletSummary.fromJson(Map<String, dynamic> j) => WalletSummary(
    walletNumber: jStr(j['walletNumber']) ?? '–',
    branchId: jStr(j['branchId']) ?? '',
    branchCode: jStr(j['branchCode']),
    branchName: jStr(j['branchName']),
    status: jStr(j['status']) ?? 'ACTIVE',
    available: jNum(j['availableBalance']) ?? 0,
    hold: jNum(j['holdBalance']) ?? 0,
    total: jNum(j['totalBalance']) ?? 0,
    todayCredit: jNum(j['todayCredit']) ?? 0,
    todayDebit: jNum(j['todayDebit']) ?? 0,
    monthCredit: jNum(j['monthCredit']) ?? 0,
    monthDebit: jNum(j['monthDebit']) ?? 0,
    todayCreditCommission: jNum(j['todayCreditCommission']) ?? 0,
    bookingPendingCommission: jNum(j['bookingPendingCommission']) ?? 0,
    deliveryPendingCommission: jNum(j['deliveryPendingCommission']) ?? 0,
    lastRechargeAmount: jNum(j['lastRechargeAmount']),
    lastRechargeAt: jTime(j['lastRechargeAt']),
  );
}

/// One ledger entry. `balanceBefore` / `balanceAfter` are recorded facts.
class WalletTxn {
  const WalletTxn({
    required this.id,
    required this.transactionNo,
    required this.type,
    required this.subType,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.createdAt,
    this.typeLabel,
    this.subTypeLabelText,
    this.referenceType,
    this.referenceId,
    this.remarks,
    this.paymentGateway,
    this.paymentReference,
    this.createdByName,
    this.branchName,
  });

  final String id;
  final String transactionNo;

  /// CR or DR.
  final String type;
  final String? typeLabel;
  final String subType;
  final String? subTypeLabelText;
  final num amount;
  final num balanceBefore;
  final num balanceAfter;
  final String? referenceType;
  final String? referenceId;
  final String? remarks;
  final String? paymentGateway;
  final String? paymentReference;
  final String? createdByName;
  final String? branchName;
  final DateTime createdAt;

  bool get isCredit => type == 'CR';
  String get reason => subTypeLabelText ?? subTypeLabel(subType);

  factory WalletTxn.fromJson(Map<String, dynamic> j) => WalletTxn(
    id: jStr(j['id']) ?? '',
    transactionNo: jStr(j['transactionNo']) ?? '–',
    type: jStr(j['transactionType']) ?? 'CR',
    typeLabel: jStr(j['transactionTypeLabel']),
    subType: jStr(j['subTransactionType']) ?? '',
    subTypeLabelText: jStr(j['subTransactionTypeLabel']),
    amount: jNum(j['amount']) ?? 0,
    balanceBefore: jNum(j['balanceBefore']) ?? 0,
    balanceAfter: jNum(j['balanceAfter']) ?? 0,
    referenceType: jStr(j['referenceType']),
    referenceId: jStr(j['referenceId']),
    remarks: jStr(j['remarks']),
    paymentGateway: jStr(j['paymentGateway']),
    paymentReference: jStr(j['paymentReference']),
    createdByName: jStr(j['createdByName']),
    branchName: jStr(j['branchName']),
    createdAt: jTime(j['createdAt']) ?? DateTime.now(),
  );
}

/// What checkout needs, from `POST /branch-wallet/recharge/order`.
class RechargeOrder {
  const RechargeOrder({
    required this.walletNumber,
    required this.orderId,
    required this.amountMinor,
    required this.currency,
    required this.publicKey,
    this.gateway,
  });

  final String walletNumber;
  final String orderId;
  final int amountMinor;
  final String currency;
  final String publicKey;
  final String? gateway;

  factory RechargeOrder.fromJson(Map<String, dynamic> j) => RechargeOrder(
    walletNumber: jStr(j['walletNumber']) ?? '',
    orderId: jStr(j['orderId']) ?? '',
    amountMinor: jInt(j['amountMinor']) ?? 0,
    currency: jStr(j['currency']) ?? 'INR',
    publicKey: jStr(j['publicKey']) ?? '',
    gateway: jStr(j['gateway']),
  );
}

/// One recharge (online or manual) from the recharge report.
class RechargeAttempt {
  const RechargeAttempt({
    required this.id,
    required this.transactionNo,
    required this.amount,
    required this.mode,
    required this.status,
    required this.createdAt,
    this.branchName,
    this.branchCode,
    this.gatewayOrderId,
    this.gatewayPaymentId,
    this.failureReason,
    this.remarks,
    this.recordedByName,
    this.lastCheckedAt,
    this.settledAt,
    this.bankSettlementStatus,
    this.bankSettlementUtr,
    this.bankSettlementId,
    this.bankSettledAt,
    this.settlementLastCheckedAt,
  });

  final String id;
  final String transactionNo;
  final String? branchName;
  final String? branchCode;
  final num amount;

  /// ONLINE or MANUAL.
  final String mode;

  /// PENDING, SUCCESS or FAILED.
  final String status;
  final String? gatewayOrderId;
  final String? gatewayPaymentId;
  final String? failureReason;
  final String? remarks;
  final String? recordedByName;
  final DateTime? lastCheckedAt;
  final DateTime? settledAt;

  /// AWAITING or SETTLED (online, credited recharges only).
  final String? bankSettlementStatus;
  final String? bankSettlementUtr;
  final String? bankSettlementId;
  final DateTime? bankSettledAt;
  final DateTime? settlementLastCheckedAt;
  final DateTime createdAt;

  bool get canCheck => status == 'PENDING' || bankSettlementStatus == 'AWAITING';

  factory RechargeAttempt.fromJson(Map<String, dynamic> j) => RechargeAttempt(
    id: jStr(j['id']) ?? '',
    transactionNo: jStr(j['transactionNo']) ?? '–',
    branchName: jStr(j['branchName']),
    branchCode: jStr(j['branchCode']),
    amount: jNum(j['amount']) ?? 0,
    mode: jStr(j['mode']) ?? 'ONLINE',
    status: jStr(j['status']) ?? 'PENDING',
    gatewayOrderId: jStr(j['gatewayOrderId']),
    gatewayPaymentId: jStr(j['gatewayPaymentId']),
    failureReason: jStr(j['failureReason']),
    remarks: jStr(j['remarks']),
    recordedByName: jStr(j['recordedByName']),
    lastCheckedAt: jTime(j['lastCheckedAt']),
    settledAt: jTime(j['settledAt']),
    bankSettlementStatus: jStr(j['bankSettlementStatus']),
    bankSettlementUtr: jStr(j['bankSettlementUtr']),
    bankSettlementId: jStr(j['bankSettlementId']),
    bankSettledAt: jTime(j['bankSettledAt']),
    settlementLastCheckedAt: jTime(j['settlementLastCheckedAt']),
    createdAt: jTime(j['createdAt']) ?? DateTime.now(),
  );
}

/// A branch's request to fund its wallet; nothing moves until a company admin approves.
class TopupRequest {
  const TopupRequest({
    required this.id,
    required this.branchId,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.remarks,
    this.proofImageUrl,
    this.decidedAt,
    this.decisionRemarks,
  });

  final String id;
  final String branchId;
  final num amount;

  /// PENDING, APPROVED or REJECTED.
  final String status;
  final String? remarks;
  final String? proofImageUrl;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decisionRemarks;

  factory TopupRequest.fromJson(Map<String, dynamic> j) => TopupRequest(
    id: jStr(j['id']) ?? '',
    branchId: jStr(j['branchId']) ?? '',
    amount: jNum(j['requestedAmount']) ?? 0,
    status: jStr(j['status']) ?? 'PENDING',
    remarks: jStr(j['remarks']),
    proofImageUrl: jStr(j['proofImageUrl']),
    createdAt: jTime(j['createdAt']) ?? DateTime.now(),
    decidedAt: jTime(j['decidedAt']),
    decisionRemarks: jStr(j['decisionRemarks']),
  );
}

/// Ledger filters (`GET /branch-wallet/transactions`).
class TxnFilter {
  const TxnFilter({this.search, this.from, this.to, this.types = const {}, this.subTypes = const {}, this.reference});

  final String? search;
  final DateTime? from;
  final DateTime? to;
  final Set<String> types;
  final Set<String> subTypes;
  final String? reference;

  int get activeCount =>
      (from != null ? 1 : 0) +
      (to != null ? 1 : 0) +
      (types.isNotEmpty ? 1 : 0) +
      (subTypes.isNotEmpty ? 1 : 0) +
      ((reference ?? '').isNotEmpty ? 1 : 0);

  Map<String, dynamic> query() => {
    if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
    if (from != null) 'fromDate': Fmt.apiDate(from!),
    if (to != null) 'toDate': Fmt.apiDate(to!),
    if (types.isNotEmpty) 'transactionType': types.toList(),
    if (subTypes.isNotEmpty) 'subTransactionType': subTypes.toList(),
    if ((reference ?? '').trim().isNotEmpty) 'referenceId': reference!.trim(),
  };

  TxnFilter copyWith({String? search}) =>
      TxnFilter(search: search, from: from, to: to, types: types, subTypes: subTypes, reference: reference);

  @override
  bool operator ==(Object other) => other is TxnFilter && other.query().toString() == query().toString();

  @override
  int get hashCode => query().toString().hashCode;
}
