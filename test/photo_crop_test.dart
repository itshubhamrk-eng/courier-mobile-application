import 'dart:ui' as ui;

import 'package:branch_ops/features/booking/presentation/photo_crop_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<CropResult?> run(WidgetTester t, Future<void> Function(Rect photo) act) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final r = ui.PictureRecorder();
    Canvas(r).drawColor(Colors.white, BlendMode.src);
    final image = r.endRecording().toImageSync(704, 352); // shown at half size: 352 x 176
    CropResult? result;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await Navigator.push<CropResult>(
              c,
              MaterialPageRoute(builder: (_) => PhotoCropPage(image: image)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final area = t.getRect(find.byKey(const Key('crop-area')));
    await act(Rect.fromCenter(center: area.center, width: 352, height: 176));
    await t.pumpAndSettle();
    return result;
  }

  Future<void> drag(WidgetTester t, Offset from, Offset by) => t.dragFrom(from, by, touchSlopX: 0, touchSlopY: 0);
  Future<void> use(WidgetTester t) => t.tap(find.text('Read details'));

  testWidgets('untouched keeps the whole photo', (t) async {
    final r = await run(t, (_) => use(t)) as CropDone;
    expect((r.image.width, r.image.height), (704, 352));
  });

  testWidgets('a corner crops both ways, in photo pixels', (t) async {
    final r = await run(t, (p) async {
      await drag(t, p.topLeft + const Offset(2, 2), const Offset(100, 50));
      await t.pump();
      await use(t);
    }) as CropDone;
    expect((r.image.width, r.image.height), (504, 252));
  });

  testWidgets('cannot be cropped to nothing or dragged outside the photo', (t) async {
    final r = await run(t, (p) async {
      await drag(t, p.bottomRight - const Offset(2, 2), const Offset(-900, -900));
      await t.pump();
      await drag(t, p.topLeft + const Offset(2, 2), const Offset(-900, -900));
      await t.pump();
      await use(t);
    }) as CropDone;
    expect((r.image.width, r.image.height), (128, 128));
  });

  testWidgets('rotate turns the photo and its crop; whole photo undoes the crop', (t) async {
    final r = await run(t, (p) async {
      await drag(t, p.topLeft + const Offset(2, 2), const Offset(100, 50));
      await t.tap(find.byTooltip('Rotate'));
      await t.pump();
      await t.tap(find.byTooltip('Whole photo'));
      await t.pump();
      await use(t);
    }) as CropDone;
    expect((r.image.width, r.image.height), (352, 704));
  });

  testWidgets('retake', (t) async {
    expect(await run(t, (_) => t.tap(find.text('Retake'))), isA<CropRetake>());
  });
}
