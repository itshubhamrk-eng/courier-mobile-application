import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/api_exception.dart';
import '../theme/app_theme.dart';

enum ResultKind {
  success(AppColors.success),
  warning(AppColors.warning),
  failure(AppColors.danger);

  const ResultKind(this.color);

  final Color color;

  /// Outcome of a bulk action where some rows can be refused.
  static ResultKind ofCounts({required int ok, required int failed}) => failed == 0
      ? success
      : ok == 0
      ? failure
      : warning;
}

/// Animated outcome of a submit: the disc pops in, then the tick, "!" or cross is drawn.
/// Success throws a burst in the app colours; failure shakes. Plays once, with a haptic.
class ResultMark extends StatefulWidget {
  const ResultMark(this.kind, {super.key, this.size = 72, this.onDark = false});

  final ResultKind kind;

  /// Diameter of the disc; the burst needs twice this and is painted around it.
  final double size;

  /// White disc with a coloured mark, for gradient cards.
  final bool onDark;

  @override
  State<ResultMark> createState() => _ResultMarkState();
}

class _ResultMarkState extends State<ResultMark> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) _play();
  }

  @override
  void didUpdateWidget(ResultMark old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind) _play();
  }

  void _play() {
    _started = true;
    unawaited(widget.kind == ResultKind.success ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final shake = widget.kind == ResultKind.failure
              ? math.sin(_c.value * math.pi * 8) * 8 * math.max(0, 1 - _c.value)
              : 0.0;
          return Transform.translate(
            offset: Offset(shake, 0),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _MarkPainter(_c.value, widget.kind, onDark: widget.onDark),
            ),
          );
        },
      ),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.t, this.kind, {required this.onDark});

  final double t;
  final ResultKind kind;
  final bool onDark;

  static const _burst = [
    AppColors.primary,
    AppColors.amber,
    AppColors.purple,
    AppColors.teal,
    AppColors.pink,
    AppColors.indigo,
  ];

  double _part(double from, double to, Curve curve) => curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final pop = _part(0, 0.45, Curves.easeOutBack);
    final draw = _part(0.3, 0.7, Curves.easeOut);
    final out = _part(0.3, 1, Curves.easeOutCubic);
    final base = onDark ? Colors.white : kind.color;

    // Ring that spreads and fades.
    if (out > 0 && out < 1) {
      canvas.drawCircle(
        c,
        r * (1 + 0.45 * out),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - out)
          ..color = base.withValues(alpha: 0.6 * (1 - out)),
      );
      if (kind == ResultKind.success) {
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          canvas.drawCircle(
            c + Offset(math.cos(a), math.sin(a)) * r * (1 + (i.isEven ? 0.75 : 0.5) * out),
            r * 0.15 * (1 - 0.5 * out),
            Paint()
              ..color = (onDark ? Colors.white : _burst[i % _burst.length]).withValues(
                alpha: 1 - _part(0.65, 1, Curves.linear),
              ),
          );
        }
      }
    }

    canvas.drawCircle(c, r * pop, Paint()..color = base);
    if (draw == 0) return;

    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = r * 0.17
      ..color = onDark ? kind.color : Colors.white;
    Offset p(double x, double y) => c + Offset(x * r, y * r);
    final path = Path();
    switch (kind) {
      case ResultKind.success:
        path.addPolygon([p(-0.42, 0.04), p(-0.12, 0.34), p(0.44, -0.3)], false);
      case ResultKind.warning:
        path
          ..addPolygon([p(0, -0.48), p(0, 0.14)], false)
          ..addPolygon([p(0, 0.43), p(0, 0.45)], false);
      case ResultKind.failure:
        path
          ..addPolygon([p(-0.32, -0.32), p(0.32, 0.32)], false)
          ..addPolygon([p(0.32, -0.32), p(-0.32, 0.32)], false);
    }
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * draw), pen);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t || old.kind != kind || old.onDark != onDark;
}

OverlayEntry? _current;

/// Animated "saved" card over whatever page comes next. Closes by itself or on a tap.
void showSubmitSuccess(BuildContext context, String message, {String title = 'Success'}) =>
    _show(context, ResultKind.success, title, message);

/// Animated failure card for a refused submit. Stays until dismissed, so the reason is read.
void showSubmitFailure(BuildContext context, Object error, {String title = 'Not completed'}) => _show(
  context,
  ResultKind.failure,
  title,
  error is ApiException && error.message.isNotEmpty ? error.message : 'Something went wrong.',
);

/// An overlay rather than a route, so a page that pops or replaces itself right after
/// submitting can never pop this card instead.
void _show(BuildContext context, ResultKind kind, String title, String message) {
  FocusManager.instance.primaryFocus?.unfocus();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  _close(_current);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ResultCard(kind: kind, title: title, message: message, onClose: () => _close(entry)),
  );
  _current = entry;
  Overlay.of(context, rootOverlay: true).insert(entry);
}

void _close(OverlayEntry? entry) {
  if (entry == null || _current != entry) return;
  _current = null;
  if (entry.mounted) entry.remove();
}

class _ResultCard extends StatefulWidget {
  const _ResultCard({required this.kind, required this.title, required this.message, required this.onClose});

  final ResultKind kind;
  final String title;
  final String message;
  final VoidCallback onClose;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Timer? _auto;
  bool _closing = false;

  bool get _failure => widget.kind == ResultKind.failure;

  @override
  void initState() {
    super.initState();
    _c.forward();
    if (!_failure) _auto = Timer(const Duration(milliseconds: 2200), _close);
  }

  @override
  void dispose() {
    _auto?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _auto?.cancel();
    await _c.reverse().orCancel.catchError((_) {});
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) => BackButtonListener(
    onBackButtonPressed: () async {
      unawaited(_close());
      return true;
    },
    child: FadeTransition(
      opacity: _c,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const ColoredBox(color: AppColors.scrim),
              ),
            ),
            Center(
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    margin: const EdgeInsets.all(32),
                    constraints: BoxConstraints(maxWidth: 340, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ResultMark(widget.kind, size: 80),
                          const SizedBox(height: 32),
                          Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: widget.kind.color),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.textPrimary),
                          ),
                          if (_failure) ...[
                            const SizedBox(height: 20),
                            FilledButton(onPressed: _close, child: const Text('OK')),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
