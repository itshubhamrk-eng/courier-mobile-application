import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';

sealed class CropResult {
  const CropResult();
}

class CropRetake extends CropResult {
  const CropRetake();
}

class CropDone extends CropResult {
  const CropDone(this.image);

  final ui.Image image;
}

/// Shows the photo just taken; drag the corners or edges to keep only the details, drag
/// inside to move the box. Pops a [CropResult], or null when closed.
class PhotoCropPage extends StatefulWidget {
  const PhotoCropPage({super.key, required this.image, this.retakeLabel = 'Retake'});

  final ui.Image image;
  final String retakeLabel;

  @override
  State<PhotoCropPage> createState() => _PhotoCropPageState();
}

class _PhotoCropPageState extends State<PhotoCropPage> {
  late ui.Image _image = widget.image;

  /// The kept part, in photo pixels.
  late Rect _crop = _full;

  /// Which sides the current drag moves: -1 left / top, 1 right / bottom, 0 neither.
  (int, int)? _grab;
  bool _moving = false;

  Rect get _full => Offset.zero & Size(_image.width.toDouble(), _image.height.toDouble());

  ui.Image _draw(int width, int height, void Function(Canvas canvas) paint) {
    final recorder = ui.PictureRecorder();
    paint(Canvas(recorder));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  void _rotate() => setState(() {
    final old = _image;
    _image = _draw(old.height, old.width, (c) {
      c
        ..translate(old.height.toDouble(), 0)
        ..rotate(math.pi / 2)
        ..drawImage(old, Offset.zero, Paint());
    });
    _crop = Rect.fromLTRB(old.height - _crop.bottom, _crop.left, old.height - _crop.top, _crop.right);
  });

  void _use() {
    final src = Rect.fromLTRB(
      _crop.left.floorToDouble(),
      _crop.top.floorToDouble(),
      _crop.right.ceilToDouble(),
      _crop.bottom.ceilToDouble(),
    ).intersect(_full);
    final image = _draw(
      src.width.round(),
      src.height.round(),
      (c) => c.drawImageRect(_image, src, Offset.zero & src.size, Paint()..filterQuality = FilterQuality.high),
    );
    Navigator.pop(context, CropDone(image));
  }

  void _start(Offset p, Rect box) {
    const reach = 32.0;
    // The nearest edge, when both of a small box are in reach.
    int side(double v, double lo, double hi) {
      final a = (v - lo).abs(), b = (v - hi).abs();
      if (math.min(a, b) > reach) return 0;
      return a <= b ? -1 : 1;
    }

    final near = box.inflate(reach).contains(p);
    _grab = near ? (side(p.dx, box.left, box.right), side(p.dy, box.top, box.bottom)) : null;
    _moving = _grab == (0, 0);
  }

  void _drag(Offset d, double scale) {
    final g = _grab;
    if (g == null) return;
    final delta = d / scale;
    setState(() {
      if (_moving) {
        _crop = _crop.translate(
          delta.dx.clamp(-_crop.left, _full.right - _crop.right),
          delta.dy.clamp(-_crop.top, _full.bottom - _crop.bottom),
        );
        return;
      }
      // Never smaller than a finger can grab again, nor than the reader needs.
      final min = math.min(math.max(48.0, 64 / scale), _full.shortestSide);
      var Rect(:left, :top, :right, :bottom) = _crop;
      if (g.$1 < 0) left = (left + delta.dx).clamp(0.0, math.max(0.0, right - min));
      if (g.$1 > 0) right = (right + delta.dx).clamp(math.min(_full.right, left + min), _full.right);
      if (g.$2 < 0) top = (top + delta.dy).clamp(0.0, math.max(0.0, bottom - min));
      if (g.$2 > 0) bottom = (bottom + delta.dy).clamp(math.min(_full.bottom, top + min), _full.bottom);
      _crop = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      flexibleSpace: const AppBarGradient(),
      title: const Text('Crop photo'),
      actions: [
        IconButton(tooltip: 'Rotate', onPressed: _rotate, icon: const Icon(Icons.rotate_90_degrees_cw_outlined)),
        IconButton(
          tooltip: 'Whole photo',
          onPressed: _crop == _full ? null : () => setState(() => _crop = _full),
          icon: const Icon(Icons.fullscreen),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Drag the corners so only the name, address and mobile number are inside.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, c) {
                  final fitted = applyBoxFit(BoxFit.contain, _full.size, c.biggest).destination;
                  final origin = Alignment.center.inscribe(fitted, Offset.zero & c.biggest).topLeft;
                  final scale = fitted.width / _full.width;
                  Rect box() => Rect.fromLTRB(
                    _crop.left * scale,
                    _crop.top * scale,
                    _crop.right * scale,
                    _crop.bottom * scale,
                  ).shift(origin);
                  return GestureDetector(
                    key: const Key('crop-area'),
                    behavior: HitTestBehavior.opaque,
                    // Down, not start: start is reported only after the finger has moved away.
                    onPanDown: (d) => _start(d.localPosition, box()),
                    onPanUpdate: (d) => _drag(d.delta, scale),
                    child: CustomPaint(size: c.biggest, painter: _CropPainter(_image, origin & fitted, box())),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    onPressed: () => Navigator.pop(context, const CropRetake()),
                    icon: const Icon(Icons.refresh),
                    label: Text(widget.retakeLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _use,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Read details'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.image, this.photo, this.box);

  final ui.Image image;
  final Rect photo;
  final Rect box;

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(canvas: canvas, rect: photo, image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(photo)
        ..addRect(box),
      Paint()..color = Colors.black54,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawRect(box, line);
    final arm = math.min(24.0, box.shortestSide / 3);
    final handle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = AppColors.amber;
    for (final (p, x, y) in [
      (box.topLeft, 1, 1),
      (box.topRight, -1, 1),
      (box.bottomLeft, 1, -1),
      (box.bottomRight, -1, -1),
    ]) {
      canvas
        ..drawLine(p, p + Offset(arm * x, 0), handle)
        ..drawLine(p, p + Offset(0, arm * y), handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.image != image || old.photo != photo || old.box != box;
}
