import 'package:url_launcher/url_launcher.dart';

import '../../../core/format.dart';
import '../../masters/data/masters.dart';

/// "Collect ₹X (COD / To-Pay)" when the payment mode is collected at delivery,
/// using the server's own payment-mode flags and net amount.
String? collectLabel(String? paymentModeId, num? netAmount, List<Option> modes) {
  final mode = modes.where((m) => m.id == paymentModeId).firstOrNull;
  if (mode == null) return null;
  final cod = mode.flags['cashOnDelivery'] == true;
  final toPay = mode.flags['collectAtDelivery'] == true;
  if (!cod && !toPay) return null;
  return 'Collect ${Fmt.money(netAmount)} (${cod ? 'COD' : 'To-Pay'})';
}

Future<bool> callNumber(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

/// Opens the address in Google Maps (or the browser when Maps is not installed).
Future<bool> openInMaps(String address) => launchUrl(
  Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address}),
  mode: LaunchMode.externalApplication,
);
