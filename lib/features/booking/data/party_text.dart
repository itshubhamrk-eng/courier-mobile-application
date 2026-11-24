import 'dart:math' as math;
import 'dart:ui';

enum PartySide {
  sender('Sender'),
  receiver('Receiver');

  const PartySide(this.label);

  final String label;
}

/// One line of text read from a photo, with its place in the photo.
class TextLine {
  const TextLine(this.text, [this.box = Rect.zero]);

  final String text;
  final Rect box;
}

class PartyDetails {
  const PartyDetails({this.name = '', this.contact = '', this.address = '', this.pincode = ''});

  final String name;
  final String contact;
  final String address;
  final String pincode;

  bool get isEmpty => name.isEmpty && contact.isEmpty && address.isEmpty && pincode.isEmpty;
}

/// What a photo says. With From / To markers each side gets its own part; without
/// them the whole text belongs to the side the user asked for.
class PhotoParties {
  const PhotoParties(this._parts, this.rawText);

  final Map<PartySide, PartyDetails> _parts;
  final String rawText;

  PartyDetails of(PartySide side) => _parts[side] ?? const PartyDetails();
  bool has(PartySide side) => !of(side).isEmpty;
}

// "\b" is ASCII only, so Hindi / Marathi markers are closed by a separator or line end.
final _from = RegExp(
  r'^\W{0,3}(?:(?:ship(?:ped)?\s+)?from|sender|consignor|shipper|प्रेषक)(?:\s*(?:name|details|address))?\s*(?:[:\-–.]+|$)\s*',
  caseSensitive: false,
);
final _to = RegExp(
  r'^\W{0,3}(?:(?:ship(?:ped)?\s+|deliver(?:y)?\s+)?to|receiver|consignee|recipient|प्रति|प्राप्तकर्ता)(?:\s*(?:name|details|address))?\s*(?:[:\-–.,]+|$)\s*',
  caseSensitive: false,
);

PhotoParties parsePhoto(List<TextLine> input, PartySide asked) {
  final lines = [
    for (final l in input)
      if (l.text.trim().isNotEmpty) TextLine(_asciiDigits(l.text.trim()), l.box),
  ];
  final raw = input.map((l) => l.text.trim()).where((t) => t.isNotEmpty).join('\n');
  final from = lines.where((l) => _from.hasMatch(l.text)).firstOrNull;
  final to = lines.where((l) => _to.hasMatch(l.text)).firstOrNull;

  if (from != null && to != null && _sideBySide(from.box, to.box)) {
    final fromLeft = from.box.left < to.box.left;
    final split = math.max(from.box.left, to.box.left) - 0.5 * math.max(from.box.height, to.box.height);
    final top = math.min(from.box.top, to.box.top);
    final body = lines.where((l) => l.box.bottom > top);
    List<String> column(bool left) => [
      for (final l in body)
        if ((l.box.left < split) == left) l.text,
    ];
    return PhotoParties({
      PartySide.sender: parseParty(column(fromLeft)),
      PartySide.receiver: parseParty(column(!fromLeft)),
    }, raw);
  }

  final parts = <PartySide, List<String>>{};
  PartySide? current;
  for (final l in lines) {
    if (_from.hasMatch(l.text)) current = PartySide.sender;
    if (_to.hasMatch(l.text)) current = PartySide.receiver;
    if (current != null) parts.putIfAbsent(current, () => []).add(l.text);
  }
  // No markers, or only the other side's: do not lose what the user photographed.
  if (parts[asked] == null && parts.length <= 1) {
    return PhotoParties({asked: parseParty(lines.map((l) => l.text).toList())}, raw);
  }
  return PhotoParties({for (final e in parts.entries) e.key: parseParty(e.value)}, raw);
}

bool _sideBySide(Rect a, Rect b) {
  if (a.isEmpty || b.isEmpty) return false;
  return (a.center.dy - b.center.dy).abs() < math.max(a.height, b.height) && (a.right <= b.left || b.right <= a.left);
}

final _phone = RegExp(r'(?<!\d)(?:\+?\s*91[\s\-]*|0)?([6-9](?:[\s\-]?\d){9})(?!\d)');
final _pin = RegExp(r'(?<!\d)([1-9]\d{2})[\s\-]?(\d{3})(?!\d)');
final _pinLabel = RegExp(
  r'(?:\bpin\s*-?\s*(?:code)?|\bzip|पिन\s*(?:कोड)?)\s*(?:no\.?)?\s*[:\-–.]*\s*$',
  caseSensitive: false,
);
final _nameLabel = RegExp(r'^(?:customer\s+|party\s+|full\s+)?(?:name|नाव|नाम)\s*[:\-–.]+\s*', caseSensitive: false);
final _addressLabel = RegExp(r'^(?:full\s+)?(?:address|addr|add|पत्ता|पता)\s*[:\-–.]+\s*', caseSensitive: false);
final _phoneLabel = RegExp(
  r'(?:\b(?:mobile|mob|phone|ph|contact|cell|tel|whatsapp|m)\b|मोबाईल|मोबाइल|फोन|संपर्क)[\s.]*(?:number\b|no\b|नं)?[\s.:\-–/,]*$',
  caseSensitive: false,
);
final _noise = RegExp(
  r'@|\bwww\.|https?:|\bgst(?:in)?\b|\bpan\s*no|\bawb\b|\binvoice\b|\bdate\b|\bweight\b|\bqty\b',
  caseSensitive: false,
);
final _addressWord = RegExp(
  r'\b(?:road|rd|street|st|lane|nagar|colony|society|soc|flat|plot|shop|near|opp|behind|floor|bldg|building|apartment|apt|'
  r'chowk|market|dist|district|taluka|tal|tq|village|post|sector|phase|gali|complex|marg|house|h\.?\s?no|at)\b',
  caseSensitive: false,
);

/// Best guess at one party from its lines; the user always checks it before it is used.
PartyDetails parseParty(List<String> input) {
  var contact = '';
  var pincode = '';
  var name = '';
  var labelled = false;
  final rest = <String>[];

  final lines = [
    for (final l in input) _fixDigits(_asciiDigits(l.replaceFirst(_from, '').replaceFirst(_to, '').trim())),
  ];

  // A pincode right after its label beats any other six digits (a plot or bill number);
  // otherwise the last one, as addresses end with it.
  RegExpMatch? best;
  int? bestLine;
  for (var i = 0; i < lines.length; i++) {
    final masked = lines[i].replaceAllMapped(_phone, (m) => 'x' * m[0]!.length);
    if (_noise.hasMatch(masked)) continue;
    for (final m in _pin.allMatches(masked)) {
      best = m;
      bestLine = i;
      if (_pinLabel.hasMatch(masked.substring(0, m.start))) {
        labelled = true;
        break;
      }
    }
    if (labelled) break;
  }
  if (best != null) pincode = '${best[1]}${best[2]}';

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (i == bestLine) {
      line = '${line.substring(0, best!.start).replaceFirst(_pinLabel, '')}${line.substring(best.end)}';
    }
    // First mobile number wins; any others are dropped from the address too.
    final phones = _phone.allMatches(line).toList();
    if (contact.isEmpty && phones.isNotEmpty) contact = phones.first[1]!.replaceAll(RegExp(r'\D'), '');
    for (final m in phones.reversed) {
      line = '${line.substring(0, m.start).replaceFirst(_phoneLabel, '')}${line.substring(m.end)}';
    }
    if (_noise.hasMatch(line)) continue;
    if (name.isEmpty && _nameLabel.hasMatch(line)) {
      name = _tidy(line.replaceFirst(_nameLabel, ''));
      continue;
    }
    final isAddress = _addressLabel.hasMatch(line);
    line = _tidy(line.replaceFirst(_addressLabel, ''));
    if (line.isEmpty || !RegExp(r'\p{L}', unicode: true).hasMatch(line)) continue;
    if (RegExp(r'^(?:pin\s*(?:code)?|mobile|mob|phone|name|address)$', caseSensitive: false).hasMatch(line)) continue;
    rest.add(isAddress ? '\u0000$line' : line);
  }

  if (name.isEmpty) {
    final i = rest.indexWhere(
      (l) => !l.startsWith('\u0000') && !RegExp(r'^\d').hasMatch(l) && !_addressWord.hasMatch(l),
    );
    // Only near the top: a city on the last line is not a name.
    if (i == 0 || (i == 1 && rest.length > 2)) name = rest.removeAt(i);
  }
  return PartyDetails(
    name: name,
    contact: contact,
    address: rest.map((l) => l.replaceAll('\u0000', '')).join(', '),
    pincode: pincode,
  );
}

String _tidy(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[\s,.:;\-–|/]+|[\s,:;\-–|/]+$'), '').trim();

String _asciiDigits(String s) =>
    s.replaceAllMapped(RegExp('[०-९]'), (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0966 + 0x30));

/// Letters read in place of digits (O for 0, l for 1), only in long words at least two-thirds digits.
String _fixDigits(String s) => s.replaceAllMapped(RegExp(r'[0-9OolISB]{6,}'), (m) {
  final w = m[0]!;
  if (RegExp(r'\D').allMatches(w).length * 3 > w.length) return w;
  return w.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[lI]'), '1').replaceAll('S', '5').replaceAll('B', '8');
});
