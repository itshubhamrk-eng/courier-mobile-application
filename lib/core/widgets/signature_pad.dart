import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';

class SignaturePadController extends ChangeNotifier {
  final _strokes = <List<Offset>>[];
  final _key = GlobalKey();

  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// PNG of the signature on white, or null when nothing was drawn.
  Future<Uint8List?> toPng() async {
    if (isEmpty) return null;
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }
}

/// Finger-drawn signature box.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.controller, this.height = 160});

  final SignaturePadController controller;
  final double height;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_redraw);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: RepaintBoundary(
          key: c._key,
          child: GestureDetector(
            onPanStart: (d) => setState(() => c._strokes.add([d.localPosition])),
            onPanUpdate: (d) => setState(() => c._strokes.last.add(d.localPosition)),
            child: CustomPaint(
              painter: _Painter(c._strokes),
              child: c.isEmpty
                  ? const Center(
                      child: Text('Receiver signs here', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
