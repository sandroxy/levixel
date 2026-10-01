import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandrox_levixel/levixel.dart';

Future<void> pumpNativeWork(
    WidgetTester tester, bool Function() completed) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 200 && !completed(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  });
  expect(completed(), isTrue);
}

void main() {
  testWidgets('a tapped duplicate exports its decoded image and geometry',
      (tester) async {
    const channel = MethodChannel('com.sandrox.levixel/flutter');
    final calls = <MethodCall>[];
    var opened = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'open') {
        opened = true;
      }
      return null;
    });
    final image = (await tester.runAsync(
        () => createTestImage(width: 160, height: 80, cache: false)))!;
    final controller = LevixelController(galleryId: 'duplicates', items: [
      LevixelMedia(
          id: 'photo', type: LevixelMediaType.image, url: 'file:///photo.png')
    ]);
    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final key in ['left', 'right'])
              LevixelSource(
                key: ValueKey<String>(key),
                controller: controller,
                itemId: 'photo',
                cornerRadius: 12,
                child: RawImage(
                    image: image, width: 100, height: 80, fit: BoxFit.cover),
              ),
          ]),
        ),
      ));
      final tapped = find.byKey(const ValueKey<String>('right'));
      final rendered =
          find.descendant(of: tapped, matching: find.byType(RawImage));
      final bounds = tester.getRect(rendered);
      await tester.tap(tapped);
      await pumpNativeWork(tester, () => opened);
      final prepared = calls
          .firstWhere((call) => call.method == 'prepare')
          .arguments as Map<Object?, Object?>;
      final sources =
          (prepared['sources']! as List<Object?>).cast<Map<Object?, Object?>>();
      expect(sources, hasLength(2));
      expect(sources.map((source) => source['sourceId']).toSet(), hasLength(2));
      final selected = sources
          .singleWhere((source) => source['sourceId'] == prepared['sourceId']);
      expect(selected['itemId'], 'photo');
      expect(selected['frame'],
          [bounds.left, bounds.top, bounds.width, bounds.height]);
      expect(selected['clip'], selected['frame']);
      expect(selected['cornerRadius'], 12);
      expect(selected['fit'], 'cover');
      expect(selected['opacity'], 1);
      final png = selected['png']! as Uint8List;
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final dimensions = ByteData.sublistView(png);
      expect(dimensions.getUint32(16), 160);
      expect(dimensions.getUint32(20), 80);
      final opacity =
          find.descendant(of: tapped, matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(opacity).opacity, 0);
      final otherOpacity = find.descendant(
          of: find.byKey(const ValueKey<String>('left')),
          matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(otherOpacity).opacity, 1);
      var closed = false;
      final closing = controller.close().then((_) {
        closed = true;
      });
      await pumpNativeWork(tester, () => closed);
      await closing;
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(tester.takeException(), isNull);
    } finally {
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      image.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('host opacity updates preserve a hidden source identity',
      (tester) async {
    const channel = MethodChannel('com.sandrox.levixel/flutter');
    final calls = <MethodCall>[];
    var opened = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'open') {
        opened = true;
      }
      return null;
    });
    final image = (await tester.runAsync(
        () => createTestImage(width: 160, height: 80, cache: false)))!;
    final controller = LevixelController(galleryId: 'opacity', items: [
      LevixelMedia(
          id: 'photo', type: LevixelMediaType.image, url: 'file:///photo.png')
    ]);
    var hostOpacity = 0.8;
    late StateSetter rebuild;
    List<Map<Object?, Object?>>? latestSources() {
      final updates = calls.where((call) => call.method == 'updateSources');
      if (updates.isEmpty) {
        return null;
      }
      final value = updates.last.arguments as Map<Object?, Object?>;
      return (value['sources']! as List<Object?>).cast<Map<Object?, Object?>>();
    }

    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return Center(
            child: Opacity(
              opacity: hostOpacity,
              child: LevixelSource(
                key: const ValueKey<String>('source'),
                controller: controller,
                itemId: 'photo',
                child: FadeTransition(
                  opacity: const AlwaysStoppedAnimation<double>(0.75),
                  child: RawImage(
                      image: image,
                      width: 100,
                      height: 80,
                      fit: BoxFit.cover,
                      opacity: const AlwaysStoppedAnimation<double>(0.5)),
                ),
              ),
            ),
          );
        }),
      ));
      final source = find.byKey(const ValueKey<String>('source'));
      final visibility =
          find.descendant(of: source, matching: find.byType(Opacity));
      await tester.tap(source);
      await pumpNativeWork(tester, () => opened);
      final prepared = calls
          .firstWhere((call) => call.method == 'prepare')
          .arguments as Map<Object?, Object?>;
      final initial = (prepared['sources']! as List<Object?>).single
          as Map<Object?, Object?>;
      expect(initial['opacity'], closeTo(0.3, 0.000001));
      expect(tester.widget<Opacity>(visibility).opacity, 0);

      rebuild(() => hostOpacity = 0.6);
      await pumpNativeWork(tester, () {
        final sources = latestSources();
        return sources != null &&
            sources.length == 1 &&
            ((sources.single['opacity']! as double) - 0.225).abs() < 0.000001;
      });
      expect(latestSources()!.single['sourceId'], initial['sourceId']);
      expect(tester.widget<Opacity>(visibility).opacity, 0,
          reason:
              'A style update must not release the native visibility lease');

      rebuild(() => hostOpacity = 0);
      await pumpNativeWork(tester, () => latestSources()?.isEmpty ?? false);
      rebuild(() => hostOpacity = 0.4);
      await pumpNativeWork(tester, () => latestSources()?.length == 1);
      expect(latestSources()!.single['sourceId'], initial['sourceId']);
      expect(latestSources()!.single['opacity'], closeTo(0.15, 0.000001));

      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      await pumpNativeWork(tester, () => closed);
      await closing;
      expect(tester.widget<Opacity>(visibility).opacity, 1);
      expect(hostOpacity, 0.4);
      expect(tester.takeException(), isNull);
    } finally {
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      image.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
