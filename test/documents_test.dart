import 'dart:io';
import 'dart:typed_data';

import 'package:branch_ops/features/documents/pdf_documents.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  late pw.ThemeData theme;
  setUpAll(() {
    ByteData font(String f) => ByteData.view(File('assets/fonts/$f').readAsBytesSync().buffer);
    theme = pdfTheme(font('Roboto-Regular.ttf'), font('Roboto-Bold.ttf'));
  });

  const letterhead = Letterhead(name: 'Test Couriers', address: '1 Main Road, Pune', gstNumber: '27ABCDE1234F1Z5');

  bool isPdf(Uint8List b) => String.fromCharCodes(b.take(5)) == '%PDF-';
  int pages(Uint8List b) => RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(b)).length;

  test('package id matches the web label scheme', () {
    expect(packageId('AL10041', 2), 'AL10041-002');
  });

  test('one label page per package', () async {
    final pdf = await buildLabels(
      const LabelData(
        companyName: 'Test Couriers',
        trackingNumber: 'AL10041',
        shipmentNumber: 'PUN-1',
        packages: 3,
        receiverName: 'Sai Medicals',
        toLabel: 'Satara',
        weight: 12.5,
        paymentMode: 'To Pay',
      ),
      theme,
    );
    expect(isPdf(pdf), isTrue);
    expect(pages(pdf), 3);
  });

  test('loading sheet, THC, DRS and POD render', () async {
    const rows = [
      SheetRow(
        shipmentNumber: 'PUN-1',
        trackingNumber: 'AL1',
        consignee: 'A',
        packages: 2,
        weight: 10,
        toPayAmount: 250,
      ),
      SheetRow(shipmentNumber: 'PUN-2', trackingNumber: 'AL2', consignee: 'B', packages: 1, weight: 4.5),
    ];
    final sheet = await buildSheet(
      theme: theme,
      letterhead: letterhead,
      isThc: false,
      number: 'LS-1',
      fromLabel: 'Pune',
      toLabel: 'Hub',
      rows: rows,
      generatedBy: 'Tester',
    );
    final thc = await buildSheet(
      theme: theme,
      letterhead: letterhead,
      isThc: true,
      number: 'LS-1',
      fromLabel: 'Pune',
      toLabel: 'Hub',
      rows: rows,
      vehicle: 'MH12 AB 1234',
      driver: 'Driver',
      expenses: const {'Fuel': 500, 'Toll': null},
      generatedBy: 'Tester',
    );
    final drs = await buildDrs(
      theme: theme,
      letterhead: letterhead,
      number: 'DRS-1',
      branchLabel: 'Pune',
      partner: 'Partner',
      runDate: DateTime(2026, 10, 23),
      rows: const [DrsDocRow(shipmentNumber: 'PUN-1', trackingNumber: 'AL1', collectAmount: 1250)],
      generatedBy: 'Tester',
    );
    final pod = await buildPod(
      theme: theme,
      letterhead: letterhead,
      trackingNumber: 'AL1',
      shipmentNumber: 'PUN-1',
      status: 'DELIVERED',
      generatedBy: 'Tester',
    );
    for (final pdf in [sheet, thc, drs, pod]) {
      expect(isPdf(pdf), isTrue);
      expect(pages(pdf), greaterThanOrEqualTo(1));
    }
  });

  test('many shipments flow onto more pages', () async {
    final pdf = await buildSheet(
      theme: theme,
      letterhead: letterhead,
      isThc: false,
      number: 'LS-2',
      fromLabel: 'Pune',
      toLabel: 'Hub',
      rows: [
        for (var i = 0; i < 80; i++) SheetRow(shipmentNumber: 'PUN-$i', trackingNumber: 'AL$i', packages: 1, weight: 1),
      ],
      generatedBy: 'Tester',
    );
    expect(pages(pdf), greaterThan(1));
  });
}
