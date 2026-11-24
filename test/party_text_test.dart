import 'dart:ui';

import 'package:branch_ops/features/booking/data/party_text.dart';
import 'package:flutter_test/flutter_test.dart';

List<TextLine> _lines(String s) => [for (final l in s.trim().split('\n')) TextLine(l)];

void _expect(PartyDetails p, String name, String contact, String address, String pin) {
  expect((p.name, p.contact, p.address, p.pincode), (name, contact, address, pin));
}

void main() {
  test('plain address block', () {
    final p = parsePhoto(
      _lines('Sai Medicals\nShop No 4, Station Road\nSatara, Maharashtra - 415 001\nMob: +91 98765 43210'),
      PartySide.receiver,
    );
    _expect(
      p.of(PartySide.receiver),
      'Sai Medicals',
      '9876543210',
      'Shop No 4, Station Road, Satara, Maharashtra',
      '415001',
    );
    expect(p.has(PartySide.sender), isFalse);
  });

  test('labelled fields, GSTIN and e-mail ignored', () {
    final p = parseParty([
      'Name: Ravi Kumar',
      'Address: 12 MG Road, Plot 400123',
      'Pune',
      'Pin Code: 411001',
      'GSTIN 27ABCDE1234F1Z5',
      'ravi@example.com',
      'Contact No. 9123456780 / 9000000001',
    ]);
    _expect(p, 'Ravi Kumar', '9123456780', '12 MG Road, Plot 400123, Pune', '411001');
  });

  test('From and To one under the other', () {
    final p = parsePhoto(
      _lines('FROM:\nPatil Agro\nKolhapur 416001\n9822011111\nTO: Om Textiles\nLaxmi Road, Pune 411030\nPh 9890011122'),
      PartySide.sender,
    );
    _expect(p.of(PartySide.sender), 'Patil Agro', '9822011111', 'Kolhapur', '416001');
    _expect(p.of(PartySide.receiver), 'Om Textiles', '9890011122', 'Laxmi Road, Pune', '411030');
  });

  test('From and To side by side use their place in the photo', () {
    TextLine at(String t, double x, double y) => TextLine(t, Rect.fromLTWH(x, y, 150, 20));
    final p = parsePhoto([
      at('From', 10, 10),
      at('To', 300, 12),
      at('Patil Agro', 10, 40),
      at('Om Textiles', 300, 40),
      at('Kolhapur 416001', 10, 70),
      at('Laxmi Road 411030', 300, 70),
      at('9822011111', 10, 100),
      at('9890011122', 300, 100),
    ], PartySide.receiver);
    _expect(p.of(PartySide.sender), 'Patil Agro', '9822011111', 'Kolhapur', '416001');
    _expect(p.of(PartySide.receiver), 'Om Textiles', '9890011122', 'Laxmi Road', '411030');
  });

  test('Marathi with Devanagari digits', () {
    final p = parsePhoto(
      _lines('नाव: रवी पाटील\nपत्ता: लक्ष्मी रोड, पुणे\nपिन कोड: ४११०३०\nमोबाईल: ९८९००१११२२'),
      PartySide.receiver,
    );
    _expect(p.of(PartySide.receiver), 'रवी पाटील', '9890011122', 'लक्ष्मी रोड, पुणे', '411030');
  });

  test('letters read for digits are fixed only inside numbers', () {
    final p = parseParty(['Bobs Oils', 'Solapur Road', '41lO30', '98900lll22']);
    expect(p.contact, '9890011122');
    expect(p.name, 'Bobs Oils');
    expect(p.address, 'Solapur Road');
    expect(p.pincode, '411030');
  });

  test('names starting like a marker are not markers', () {
    final p = parsePhoto(_lines('Tone Traders\nFromage Foods\nSatara 415001'), PartySide.receiver);
    expect(p.of(PartySide.receiver).name, 'Tone Traders');
  });

  test('nothing readable', () {
    expect(parsePhoto(const [], PartySide.sender).has(PartySide.sender), isFalse);
  });
}
