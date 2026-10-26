import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// PDF layouts for the branch documents. Pure functions of server data:
/// nothing here calculates freight, totals owed or statuses beyond adding up
/// the rows it is given. Layout follows the web app's print views.

class Letterhead {
  const Letterhead({required this.name, this.address, this.gstNumber, this.mobile});

  final String name;
  final String? address;
  final String? gstNumber;
  final String? mobile;
}

final _date = DateFormat('dd/MM/yyyy');
final _dateTime = DateFormat('dd/MM/yyyy hh:mm a');
final _money = NumberFormat('#,##,##0.00', 'en_IN');

String _d(DateTime? v) => v == null ? '—' : _date.format(v.toLocal());
String _dt(DateTime? v) => v == null ? '—' : _dateTime.format(v.toLocal());
String _m(num? v) => v == null ? '' : '₹${_money.format(v)}';
String _kg(num? v) => v == null ? '—' : '${v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')} kg';

pw.ThemeData pdfTheme(ByteData regular, ByteData bold) =>
    pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));

pw.Widget _letterhead(Letterhead l, String title, String number) => pw.Container(
  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
  // Not stretch: a stretched row has no height bound inside MultiPage.
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(l.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if (l.address != null) pw.Text(l.address!, style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                [if (l.gstNumber != null) 'GSTIN ${l.gstNumber}', if (l.mobile != null) 'Ph ${l.mobile}'].join('   '),
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
      ),
      pw.Container(
        width: 170,
        padding: const pw.EdgeInsets.all(8),
        decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.8))),
        child: pw.Column(
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(number, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: number, height: 22, drawText: false),
          ],
        ),
      ),
    ],
  ),
);

pw.Widget _meta(List<(String, String)> cells) => pw.Container(
  width: double.infinity,
  decoration: const pw.BoxDecoration(
    border: pw.Border(
      left: pw.BorderSide(width: 0.8),
      right: pw.BorderSide(width: 0.8),
      bottom: pw.BorderSide(width: 0.8),
    ),
  ),
  child: pw.Wrap(
    children: [
      for (final (k, v) in cells)
        pw.Container(
          width: 190,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '$k: ',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
                pw.TextSpan(
                  text: v,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
    ],
  ),
);

pw.Widget _signatures(List<String> who) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 36),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      for (final w in who)
        pw.Column(
          children: [
            pw.Container(width: 140, height: 0.6, color: PdfColors.black),
            pw.SizedBox(height: 3),
            pw.Text(w, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
    ],
  ),
);

pw.Widget _footer(pw.Context c, String generatedBy) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(
      'Generated ${_dt(DateTime.now())} by $generatedBy',
      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
    ),
    pw.Text(
      'Page ${c.pageNumber} of ${c.pagesCount}',
      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
    ),
  ],
);

// ------------------------------------------------------------------ labels

class LabelData {
  const LabelData({
    required this.companyName,
    required this.trackingNumber,
    required this.shipmentNumber,
    required this.packages,
    this.bookingDate,
    this.fromLabel,
    this.toLabel,
    this.toPincode,
    this.senderName,
    this.receiverName,
    this.receiverContact,
    this.receiverAddress,
    this.weight,
    this.paymentMode,
    this.serviceType,
  });

  final String companyName;
  final String trackingNumber;
  final String shipmentNumber;
  final int packages;
  final DateTime? bookingDate;
  final String? fromLabel;
  final String? toLabel;
  final String? toPincode;
  final String? senderName;
  final String? receiverName;
  final String? receiverContact;
  final String? receiverAddress;
  final num? weight;
  final String? paymentMode;
  final String? serviceType;
}

/// Package id printed on each label: `<AWB>-001`, same scheme as the web label.
String packageId(String awb, int n) => '$awb-${n.toString().padLeft(3, '0')}';

/// One 4×6 inch label per package.
Future<Uint8List> buildLabels(LabelData d, pw.ThemeData theme) {
  final doc = pw.Document(theme: theme, title: 'Label ${d.trackingNumber}');
  final count = d.packages < 1 ? 1 : d.packages;
  for (var n = 1; n <= count; n++) {
    final pkg = packageId(d.trackingNumber, n);
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(4 * PdfPageFormat.inch, 6 * PdfPageFormat.inch, marginAll: 10),
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                color: PdfColors.black,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      d.companyName,
                      style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11),
                    ),
                    pw.Text(d.serviceType ?? '', style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 2),
                child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: pkg, height: 60, drawText: false),
              ),
              pw.Center(
                child: pw.Text(
                  pkg,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, letterSpacing: 1),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('AWB', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                          pw.Text(d.trackingNumber, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Shipment ${d.shipmentNumber}', style: const pw.TextStyle(fontSize: 8)),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            'Package $n of $count',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: pkg, width: 70, height: 70),
                  ],
                ),
              ),
              pw.Divider(height: 1, thickness: 0.8),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('TO', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                    pw.Text(d.receiverName ?? '', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    if (d.receiverAddress != null)
                      pw.Text(d.receiverAddress!, style: const pw.TextStyle(fontSize: 9), maxLines: 3),
                    pw.Text(
                      [d.toLabel, d.toPincode].nonNulls.join(' · '),
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    if (d.receiverContact != null)
                      pw.Text('Ph ${d.receiverContact}', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              pw.Divider(height: 1, thickness: 0.8),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('FROM', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                    pw.Text(d.senderName ?? '', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(d.fromLabel ?? '', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.8))),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Wt ${_kg(d.weight)}', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(d.paymentMode ?? '', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_d(d.bookingDate), style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  return doc.save();
}

// ------------------------------------------------------------------ loading sheet / THC

class SheetRow {
  const SheetRow({
    required this.shipmentNumber,
    required this.trackingNumber,
    this.consignor,
    this.consignee,
    this.fromCity,
    this.toCity,
    this.bookingDate,
    this.packages,
    this.weight,
    this.toPayAmount,
  });

  final String shipmentNumber;
  final String trackingNumber;
  final String? consignor;
  final String? consignee;
  final String? fromCity;
  final String? toCity;
  final DateTime? bookingDate;
  final int? packages;
  final num? weight;

  /// Freight to collect at destination (To-Pay modes only), from the server's net amount.
  final num? toPayAmount;
}

/// Loading sheet (no vehicle yet) or THC (vehicle, driver, trip expenses).
Future<Uint8List> buildSheet({
  required pw.ThemeData theme,
  required Letterhead letterhead,
  required bool isThc,
  required String number,
  required String fromLabel,
  required String toLabel,
  required List<SheetRow> rows,
  required String generatedBy,
  DateTime? createdAt,
  DateTime? dispatchedAt,
  String? vehicle,
  String? driver,
  Map<String, num?> expenses = const {},
}) {
  final doc = pw.Document(theme: theme, title: '${isThc ? 'THC' : 'Loading sheet'} $number');
  final totalPkg = rows.fold<int>(0, (s, r) => s + (r.packages ?? 0));
  final totalKg = rows.fold<num>(0, (s, r) => s + (r.weight ?? 0));
  final totalToPay = rows.fold<num>(0, (s, r) => s + (r.toPayAmount ?? 0));
  const headers = [
    'SR',
    'SHIPMENT NO',
    'AWB',
    'CONSIGNOR',
    'CONSIGNEE',
    'FROM',
    'TO',
    'BOOKED',
    'QTY',
    'WEIGHT',
    'TO PAY',
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape.copyWith(marginLeft: 24, marginRight: 24, marginTop: 24, marginBottom: 24),
      footer: (c) => _footer(c, generatedBy),
      build: (_) => [
        _letterhead(letterhead, isThc ? 'TRIP HIRE CHALLAN' : 'LOADING SHEET', number),
        _meta([
          ('From', fromLabel),
          ('To', toLabel),
          ('Created', _dt(createdAt)),
          if (isThc) ('Dispatched', _dt(dispatchedAt)),
          if (isThc) ('Vehicle', vehicle ?? '—'),
          if (isThc) ('Driver', driver ?? '—'),
          for (final e in expenses.entries)
            if (e.value != null) (e.key, _m(e.value)),
        ]),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                rows[i].shipmentNumber,
                rows[i].trackingNumber,
                rows[i].consignor ?? '',
                rows[i].consignee ?? '',
                rows[i].fromCity ?? '',
                rows[i].toCity ?? '',
                _d(rows[i].bookingDate),
                '${rows[i].packages ?? ''}',
                _kg(rows[i].weight),
                _m(rows[i].toPayAmount),
              ],
            ['', '', '', '', '', '', '', 'TOTAL', '$totalPkg', _kg(totalKg), totalToPay == 0 ? '' : _m(totalToPay)],
          ],
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignments: {
            0: pw.Alignment.center,
            8: pw.Alignment.centerRight,
            9: pw.Alignment.centerRight,
            10: pw.Alignment.centerRight,
          },
          border: pw.TableBorder.all(width: 0.5),
        ),
        _signatures(isThc ? ['Loaded by', 'Driver', 'Branch manager'] : ['Loaded by', 'Checked by']),
      ],
    ),
  );
  return doc.save();
}

// ------------------------------------------------------------------ DRS

class DrsDocRow {
  const DrsDocRow({
    required this.shipmentNumber,
    required this.trackingNumber,
    this.receiver,
    this.contact,
    this.address,
    this.payment,
    this.collectAmount,
  });

  final String shipmentNumber;
  final String trackingNumber;
  final String? receiver;
  final String? contact;
  final String? address;
  final String? payment;

  /// Amount to collect (COD / To-Pay), from the server's net amount; null when prepaid.
  final num? collectAmount;
}

Future<Uint8List> buildDrs({
  required pw.ThemeData theme,
  required Letterhead letterhead,
  required String number,
  required String branchLabel,
  required String partner,
  required DateTime runDate,
  required List<DrsDocRow> rows,
  required String generatedBy,
}) {
  final doc = pw.Document(theme: theme, title: 'DRS $number');
  final collect = rows.fold<num>(0, (s, r) => s + (r.collectAmount ?? 0));
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape.copyWith(marginLeft: 24, marginRight: 24, marginTop: 24, marginBottom: 24),
      footer: (c) => _footer(c, generatedBy),
      build: (_) => [
        _letterhead(letterhead, 'DELIVERY RUN SHEET', number),
        _meta([
          ('Branch', branchLabel),
          ('Delivery partner', partner),
          ('Run date', _d(runDate)),
          ('Shipments', '${rows.length}'),
          ('To collect', _m(collect)),
        ]),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: const [
            'SR',
            'SHIPMENT NO',
            'AWB',
            'RECEIVER',
            'CONTACT',
            'ADDRESS',
            'PAYMENT',
            'COLLECT',
            'RECEIVER SIGN',
            'STAMP',
          ],
          data: [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                rows[i].shipmentNumber,
                rows[i].trackingNumber,
                rows[i].receiver ?? '',
                rows[i].contact ?? '',
                rows[i].address ?? '',
                rows[i].payment ?? '',
                _m(rows[i].collectAmount),
                '',
                '',
              ],
          ],
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellHeight: 30,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          columnWidths: {
            5: const pw.FlexColumnWidth(2.2),
            8: const pw.FixedColumnWidth(80),
            9: const pw.FixedColumnWidth(60),
          },
          cellAlignments: {0: pw.Alignment.center, 7: pw.Alignment.centerRight},
          border: pw.TableBorder.all(width: 0.5),
        ),
        _signatures(['Delivery partner', 'Branch manager']),
      ],
    ),
  );
  return doc.save();
}

// ------------------------------------------------------------------ POD

Future<Uint8List> buildPod({
  required pw.ThemeData theme,
  required Letterhead letterhead,
  required String trackingNumber,
  required String shipmentNumber,
  required String status,
  required String generatedBy,
  String? receiverName,
  String? receiverAddress,
  DateTime? deliveredAt,
  String? podStatus,
  String? drsNumber,
  Uint8List? photo,
  Uint8List? signature,
}) {
  final doc = pw.Document(theme: theme, title: 'POD $trackingNumber');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 28, marginRight: 28, marginTop: 28, marginBottom: 28),
      build: (c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _letterhead(letterhead, 'PROOF OF DELIVERY', trackingNumber),
          _meta([
            ('Shipment', shipmentNumber),
            ('Status', status.replaceAll('_', ' ')),
            ('Delivered', _dt(deliveredAt)),
            ('Received by', receiverName ?? '—'),
            if (drsNumber != null) ('DRS', drsNumber),
            if (podStatus != null) ('POD review', podStatus),
          ]),
          if (receiverAddress != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text('Address: $receiverAddress', style: const pw.TextStyle(fontSize: 9)),
            ),
          pw.SizedBox(height: 12),
          if (photo != null)
            pw.Expanded(
              child: pw.Center(child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.contain)),
            )
          else
            pw.Text(
              'POD photo not available on this device.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          if (signature != null) ...[
            pw.SizedBox(height: 8),
            pw.Text('Receiver signature', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.Image(pw.MemoryImage(signature), height: 70),
          ],
          pw.Spacer(),
          _footer(c, generatedBy),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Wallet transaction receipt: same fields as the web app's receipt, plus a QR of the
/// transaction number so a scan finds it.
Future<Uint8List> buildWalletReceipt({
  required pw.ThemeData theme,
  required Letterhead letterhead,
  required String transactionNo,
  required bool credit,
  required num amount,
  required String reason,
  required List<(String, String)> rows,
}) {
  final accent = credit ? PdfColor.fromInt(0xFF059669) : PdfColor.fromInt(0xFFDC2626);
  final doc = pw.Document(theme: theme, title: 'Receipt $transactionNo');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5.copyWith(marginLeft: 24, marginRight: 24, marginTop: 24, marginBottom: 24),
      build: (c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(colors: [PdfColor.fromInt(0xFF4F46E5), PdfColor.fromInt(0xFF4338CA)]),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  letterhead.name,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
                if (letterhead.address != null)
                  pw.Text(letterhead.address!, style: const pw.TextStyle(fontSize: 8, color: PdfColors.white)),
                if (letterhead.gstNumber != null || letterhead.mobile != null)
                  pw.Text(
                    [
                      if (letterhead.gstNumber != null) 'GSTIN: ${letterhead.gstNumber}',
                      if (letterhead.mobile != null) 'Ph: ${letterhead.mobile}',
                    ].join('  |  '),
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
                  ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'WALLET TRANSACTION RECEIPT',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey300, letterSpacing: 1),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Text(
              '${credit ? '+' : '-'}${_m(amount)}',
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: accent),
            ),
          ),
          pw.Center(
            child: pw.Text(reason.toUpperCase(), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ),
          pw.SizedBox(height: 12),
          for (final (k, v) in rows)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.6)),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      v,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: transactionNo, width: 80, height: 80),
          ),
          pw.Center(
            child: pw.Text(transactionNo, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ),
          pw.Spacer(),
          pw.Center(
            child: pw.Text(
              'This is a system-generated receipt. Generated ${_dt(DateTime.now())}.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
