import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
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
  for (final change in ['item removal', 'opacity', 'color effect']) {
    testWidgets('source batch refreshes $change during another image encoding',
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
      final firstImage = (await tester.runAsync(
          () => createTestImage(width: 80, height: 80, cache: false)))!;
      final secondImage = (await tester.runAsync(
          () => createTestImage(width: 160, height: 80, cache: false)))!;
      final items = [
        for (final id in ['first', 'second'])
          LevixelMedia(
              id: id, type: LevixelMediaType.image, url: 'file:///$id.png')
      ];
      final controller =
          LevixelController(galleryId: 'source-batch', items: items);
      final previousImageCallback = ui.Image.onCreate;
      try {
        const opacityKey = ValueKey<String>('first-opacity');
        const imageKey = ValueKey<String>('first-image');
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Opacity(
                key: opacityKey,
                opacity: 1,
                child: LevixelSource(
                  controller: controller,
                  itemId: 'first',
                  child: RawImage(
                      key: imageKey,
                      image: firstImage,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover),
                ),
              ),
              LevixelSource(
                controller: controller,
                itemId: 'second',
                child: RawImage(
                    image: secondImage,
                    width: 100,
                    height: 80,
                    fit: BoxFit.cover),
              ),
            ]),
          ),
        ));
        final opacity =
            tester.renderObject<RenderOpacity>(find.byKey(opacityKey));
        final rendered = tester.renderObject<RenderImage>(find.byKey(imageKey));
        var changed = false;
        ui.Image.onCreate = (created) {
          previousImageCallback?.call(created);
          if (changed || created.width != secondImage.width) {
            return;
          }
          changed = true;
          // The first source has already been captured when the second image
          // is retained. Change the first source during that later capture.
          switch (change) {
            case 'item removal':
              controller.items = [items.last];
              break;
            case 'opacity':
              opacity.opacity = 0.4;
              break;
            case 'color effect':
              rendered.color = const Color(0xFF0088FF);
              break;
          }
        };
        final opening = controller.open();
        await pumpNativeWork(tester, () => opened);
        await opening;
        ui.Image.onCreate = previousImageCallback;
        expect(changed, isTrue);
        final prepared = calls
            .firstWhere((call) => call.method == 'prepare')
            .arguments as Map<Object?, Object?>;
        final sources = (prepared['sources']! as List<Object?>)
            .cast<Map<Object?, Object?>>();
        expect(prepared['items']! as List<Object?>, hasLength(2),
            reason: 'The viewer keeps the immutable opening gallery');
        if (change == 'opacity') {
          expect(sources, hasLength(2));
          expect(sources.first['itemId'], 'first');
          expect(sources.first['opacity'], 0.4);
        } else {
          expect(sources.map((source) => source['itemId']), ['second']);
          expect(prepared['sourceId'], isNull);
        }
        var closed = false;
        final closing = controller.close().then((_) => closed = true);
        await pumpNativeWork(tester, () => closed);
        await closing;
        expect(tester.takeException(), isNull);
      } finally {
        ui.Image.onCreate = previousImageCallback;
        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        firstImage.dispose();
        secondImage.dispose();
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  for (final change in ['remount', 'item rebind', 'controller switch']) {
    testWidgets('$change restores visibility and replaces the source identity',
        (tester) async {
      const channel = MethodChannel('com.sandrox.levixel/flutter');
      final calls = <MethodCall>[];
      var opens = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call);
        if (call.method == 'open') {
          opens++;
        }
        return null;
      });
      final image = (await tester.runAsync(
          () => createTestImage(width: 160, height: 80, cache: false)))!;
      final items = [
        for (final id in ['first', 'second'])
          LevixelMedia(
              id: id, type: LevixelMediaType.image, url: 'file:///$id.png')
      ];
      final original = LevixelController(galleryId: 'original', items: items);
      final replacement =
          LevixelController(galleryId: 'replacement', items: items);
      var controller = original;
      var itemId = 'first';
      var visible = true;
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
              child: visible
                  ? LevixelSource(
                      key: const ValueKey<String>('source'),
                      controller: controller,
                      itemId: itemId,
                      child: RawImage(
                          image: image,
                          width: 100,
                          height: 80,
                          fit: BoxFit.cover),
                    )
                  : const SizedBox.shrink(),
            );
          }),
        ));
        final source = find.byKey(const ValueKey<String>('source'));
        final visibility =
            find.descendant(of: source, matching: find.byType(Opacity));
        final opening = original.open();
        await pumpNativeWork(tester, () => opens == 1);
        await opening;
        final prepared = calls
            .firstWhere((call) => call.method == 'prepare')
            .arguments as Map<Object?, Object?>;
        final oldId = prepared['sourceId'];
        expect(oldId, isNotNull);
        expect(tester.widget<Opacity>(visibility).opacity, 0);

        if (change == 'remount') {
          rebuild(() => visible = false);
          await pumpNativeWork(tester, () => latestSources()?.isEmpty ?? false);
          rebuild(() => visible = true);
        } else if (change == 'item rebind') {
          rebuild(() => itemId = 'second');
        } else {
          rebuild(() => controller = replacement);
        }
        await pumpNativeWork(tester, () {
          final sources = latestSources();
          return sources != null &&
              (change == 'controller switch'
                  ? sources.isEmpty
                  : sources.length == 1 && sources.single['sourceId'] != oldId);
        });
        expect(tester.widget<Opacity>(visibility).opacity, 1);
        if (change != 'controller switch') {
          expect(latestSources()!.single['itemId'], itemId);
          expect(latestSources()!.single['png'], isA<Uint8List>(),
              reason: 'A replacement anchor must receive its own preview');
        }

        var acknowledged = false;
        final staleVisibility = tester.binding.defaultBinaryMessenger
            .handlePlatformMessage(
                channel.name,
                const StandardMethodCodec().encodeMethodCall(MethodCall(
                    'visibility', <String, Object?>{
                  'requestId': prepared['requestId'],
                  'sourceId': oldId,
                  'hidden': true,
                })),
                null)
            .then((_) => acknowledged = true);
        await pumpNativeWork(tester, () => acknowledged);
        await staleVisibility;
        expect(tester.widget<Opacity>(visibility).opacity, 1,
            reason: 'A stale native callback must not hide the replacement');

        final reopening = controller.open(itemId: itemId);
        await pumpNativeWork(tester, () => opens == 2);
        await reopening;
        final next = calls
            .lastWhere((call) => call.method == 'prepare')
            .arguments as Map<Object?, Object?>;
        expect(next['sourceId'], isNot(oldId));
        expect(next['sourceId'], isNotNull);
        expect(next['galleryId'], controller.galleryId);
        expect(tester.widget<Opacity>(visibility).opacity, 0);
        var closed = false;
        final closing = controller.close().then((_) => closed = true);
        await pumpNativeWork(tester, () => closed);
        await closing;
        expect(tester.widget<Opacity>(visibility).opacity, 1);
        expect(tester.takeException(), isNull);
      } finally {
        original.dispose();
        replacement.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        image.dispose();
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  for (final change in ['clipping', 'fit', 'color effect']) {
    testWidgets('source handoff refreshes $change changed during encoding',
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
      final controller = LevixelController(galleryId: 'paint-change', items: [
        LevixelMedia(
            id: 'photo', type: LevixelMediaType.image, url: 'file:///photo.png')
      ]);
      final previousImageCallback = ui.Image.onCreate;
      try {
        const clipKey = ValueKey<String>('clip');
        const imageKey = ValueKey<String>('image');
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ClipRect(
              key: clipKey,
              clipBehavior: Clip.none,
              child: SizedBox(
                width: 60,
                height: 80,
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 100,
                  maxWidth: 100,
                  minHeight: 80,
                  maxHeight: 80,
                  child: LevixelSource(
                    controller: controller,
                    itemId: 'photo',
                    child: RawImage(
                        key: imageKey,
                        image: image,
                        width: 100,
                        height: 80,
                        fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
        ));
        final clip = tester.renderObject<RenderClipRect>(find.byKey(clipKey));
        final rendered = tester.renderObject<RenderImage>(find.byKey(imageKey));
        final frame = tester.getRect(find.byKey(imageKey));
        final clipped = frame.intersect(tester.getRect(find.byKey(clipKey)));
        var changed = false;
        ui.Image.onCreate = (created) {
          previousImageCallback?.call(created);
          if (changed) {
            return;
          }
          changed = true;
          // Image retention/encoding starts after the initial paint snapshot.
          // Mutate actual render state there without depending on a timer.
          switch (change) {
            case 'clipping':
              clip.clipBehavior = Clip.hardEdge;
              break;
            case 'fit':
              rendered.fit = BoxFit.contain;
              break;
            case 'color effect':
              rendered.color = const Color(0xFF0088FF);
              break;
          }
        };
        final opening = controller.open();
        await pumpNativeWork(tester, () => opened);
        await opening;
        ui.Image.onCreate = previousImageCallback;
        expect(changed, isTrue);
        final prepared = calls
            .firstWhere((call) => call.method == 'prepare')
            .arguments as Map<Object?, Object?>;
        final sources = (prepared['sources']! as List<Object?>)
            .cast<Map<Object?, Object?>>();
        if (change == 'color effect') {
          expect(sources, isEmpty,
              reason: 'An unsupported effect must not export a preview');
          expect(prepared['sourceId'], isNull);
        } else {
          final source = sources.single;
          final visible = change == 'clipping' ? clipped : frame;
          expect(source['clip'],
              [visible.left, visible.top, visible.width, visible.height]);
          expect(source['fit'], change == 'fit' ? 'contain' : 'cover');
        }
        var closed = false;
        final closing = controller.close().then((_) {
          closed = true;
        });
        await pumpNativeWork(tester, () => closed);
        await closing;
        expect(tester.takeException(), isNull);
      } finally {
        ui.Image.onCreate = previousImageCallback;
        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        image.dispose();
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

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
