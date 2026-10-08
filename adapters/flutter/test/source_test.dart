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

class _InsetClipper extends CustomClipper<Rect> {
  const _InsetClipper();

  @override
  Rect getClip(Size size) => (Offset.zero & size).deflate(10);

  @override
  bool shouldReclip(_InsetClipper oldClipper) => false;
}

Widget sourcePaint(String effect, Widget child) {
  switch (effect) {
    case 'color filter':
      return ColorFiltered(
          colorFilter:
              const ColorFilter.mode(Color(0xFF0088FF), BlendMode.srcIn),
          child: child);
    case 'image filter':
    case 'disabled image filter':
      return ImageFiltered(
          enabled: effect != 'disabled image filter',
          imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: child);
    case 'shader mask':
      return ShaderMask(
          shaderCallback: (bounds) => ui.Gradient.linear(bounds.topLeft,
              bounds.bottomRight, const [Color(0xFF0088FF), Color(0xFFFF8800)]),
          child: child);
    case 'backdrop filter':
      return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2), child: child);
    case 'rounded clip':
      return ClipRRect(borderRadius: BorderRadius.circular(20), child: child);
    case 'superellipse clip':
      return ClipRSuperellipse(
          borderRadius: BorderRadius.circular(20), child: child);
    case 'custom rect clip':
      return ClipRect(clipper: const _InsetClipper(), child: child);
    case 'counter-rotated clip':
      return Transform.rotate(
          angle: 0.3,
          child: ClipRect(child: Transform.rotate(angle: -0.3, child: child)));
    case 'rounded physical clip':
      return PhysicalModel(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: child);
    case 'rectangular physical clip':
      return PhysicalModel(
          color: const Color(0xFF000000),
          clipBehavior: Clip.hardEdge,
          child: child);
    case 'overflowing rounded source':
      return SizedBox(
          width: 60,
          height: 80,
          child: OverflowBox(
              minWidth: 100,
              maxWidth: 100,
              minHeight: 80,
              maxHeight: 80,
              child: child));
    default:
      throw ArgumentError.value(effect, 'effect');
  }
}

void main() {
  testWidgets('opening does not wait for unrelated thumbnail encoding',
      (tester) async {
    const channel = MethodChannel('com.sandrox.levixel/flutter');
    final calls = <MethodCall>[];
    var opened = false;
    final images = (await tester.runAsync(() async => [
          await createTestImage(width: 80, height: 80, cache: false),
          await createTestImage(width: 160, height: 80, cache: false),
        ]))!;
    final controller = LevixelController(galleryId: 'opening', items: [
      for (final id in ['other', 'selected'])
        LevixelMedia(
            id: id, type: LevixelMediaType.image, url: 'file:///$id.png'),
    ]);
    final previousImageCallback = ui.Image.onCreate;
    var unrelatedEncodedBeforeOpen = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'open') opened = true;
      return null;
    });
    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < images.length; i++)
              LevixelSource(
                controller: controller,
                itemId: i == 0 ? 'other' : 'selected',
                child: RawImage(image: images[i], width: 100, height: 80),
              ),
          ]),
        ),
      ));
      ui.Image.onCreate = (created) {
        previousImageCallback?.call(created);
        if (!opened && created.isCloneOf(images.first)) {
          unrelatedEncodedBeforeOpen = true;
        }
      };
      final opening = controller.open(itemId: 'selected');
      await pumpNativeWork(tester, () => opened);
      await opening;
      expect(unrelatedEncodedBeforeOpen, isFalse,
          reason: 'An unrelated image must not delay the selected transition');
      await pumpNativeWork(
          tester, () => calls.any((call) => call.method == 'updateSources'));
      final update = calls
          .lastWhere((call) => call.method == 'updateSources')
          .arguments as Map<Object?, Object?>;
      expect(update['sources'], hasLength(2),
          reason:
              'Remaining sources must still register for paging and return');
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      await pumpNativeWork(tester, () => closed);
      await closing;
    } finally {
      ui.Image.onCreate = previousImageCallback;
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      for (final image in images) {
        image.dispose();
      }
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('cancelled pointer preparation is reused without opening',
      (tester) async {
    const channel = MethodChannel('com.sandrox.levixel/flutter');
    final calls = <MethodCall>[];
    var opened = 0;
    final image = (await tester.runAsync(
        () => createTestImage(width: 160, height: 80, cache: false)))!;
    final controller = LevixelController(galleryId: 'pointer', items: [
      LevixelMedia(
          id: 'photo', type: LevixelMediaType.image, url: 'file:///photo.png'),
    ]);
    final previousCreate = ui.Image.onCreate;
    final previousDispose = ui.Image.onDispose;
    final pending = <ui.Image>{};
    var createdCount = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'open') opened++;
      return null;
    });
    try {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: LevixelSource(
            controller: controller,
            itemId: 'photo',
            child: RawImage(image: image, width: 100, height: 80),
          ),
        ),
      ));
      ui.Image.onCreate = (image) {
        previousCreate?.call(image);
        pending.add(image);
        createdCount++;
      };
      ui.Image.onDispose = (image) {
        previousDispose?.call(image);
        pending.remove(image);
      };
      final source = find.byType(LevixelSource);
      final pointer = await tester.startGesture(tester.getCenter(source));
      await pumpNativeWork(tester, () => createdCount > 0 && pending.isEmpty);
      await pointer.cancel();
      expect(calls, isEmpty,
          reason: 'A cancelled pointer must not prepare a native viewer');
      createdCount = 0;
      for (var cycle = 1; cycle <= 2; cycle++) {
        await tester.tap(source);
        await pumpNativeWork(tester, () => opened == cycle);
        expect(createdCount, 0,
            reason: 'Unchanged decoded previews survive dismissal');
        var closed = false;
        final closing = controller.close().then((_) => closed = true);
        await pumpNativeWork(tester, () => closed);
        await closing;
      }
      expect(tester.takeException(), isNull);
    } finally {
      ui.Image.onCreate = previousCreate;
      ui.Image.onDispose = previousDispose;
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      image.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  for (final change in [
    'remove during prepare',
    'effect during prepare',
    'move during prepare',
    'available during prepare',
    'remove after open',
  ]) {
    testWidgets('source handoff reconciles $change', (tester) async {
      const channel = MethodChannel('com.sandrox.levixel/flutter');
      final calls = <MethodCall>[];
      var opened = false;
      var visible = true;
      Color? tint =
          change == 'available during prepare' ? const Color(0xFF0088FF) : null;
      var offset = Offset.zero;
      late StateSetter rebuild;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        calls.add(call);
        if (call.method ==
            (change == 'remove after open' ? 'open' : 'prepare')) {
          rebuild(() {
            if (change.startsWith('remove')) {
              visible = false;
            } else if (change == 'effect during prepare') {
              tint = const Color(0xFF0088FF);
            } else if (change == 'available during prepare') {
              tint = null;
            } else {
              offset = const Offset(24, 12);
            }
          });
        }
        if (call.method == 'open') {
          opened = true;
        }
        return null;
      });
      final image = (await tester.runAsync(
          () => createTestImage(width: 160, height: 80, cache: false)))!;
      final controller = LevixelController(galleryId: 'handoff', items: [
        LevixelMedia(
            id: 'photo', type: LevixelMediaType.image, url: 'file:///photo.png')
      ]);
      List<Map<Object?, Object?>>? latestSources() {
        final updates = calls.where((call) => call.method == 'updateSources');
        if (updates.isEmpty) {
          return null;
        }
        final arguments = updates.last.arguments as Map<Object?, Object?>;
        return (arguments['sources']! as List<Object?>)
            .cast<Map<Object?, Object?>>();
      }

      try {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return Center(
              child: visible
                  ? Transform.translate(
                      offset: offset,
                      child: LevixelSource(
                        controller: controller,
                        itemId: 'photo',
                        child: RawImage(
                            image: image,
                            width: 100,
                            height: 80,
                            fit: BoxFit.cover,
                            color: tint),
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          }),
        ));
        Future<void>? opening;
        if (change == 'available during prepare') {
          await tester.tap(find.byType(LevixelSource));
        } else {
          opening = controller.open();
        }
        await pumpNativeWork(tester, () => opened);
        await opening;
        final prepared = calls
            .singleWhere((call) => call.method == 'prepare')
            .arguments as Map<Object?, Object?>;
        expect(prepared['sources'],
            hasLength(change == 'available during prepare' ? 0 : 1));
        if (change == 'remove after open') {
          await pumpNativeWork(tester, () => latestSources()?.isEmpty ?? false);
        } else {
          expect(calls.indexWhere((call) => call.method == 'updateSources'),
              lessThan(calls.indexWhere((call) => call.method == 'open')));
        }
        final updated = latestSources();
        expect(updated, isNotNull);
        if (change == 'move during prepare' ||
            change == 'available during prepare') {
          final frame = tester.getRect(find.byType(RawImage));
          final source = updated!.single;
          expect(source['frame'],
              [frame.left, frame.top, frame.width, frame.height]);
          expect(
              source.containsKey('png'), change == 'available during prepare',
              reason: 'New anchors need pixels; geometry updates reuse them');
        } else {
          expect(updated, isEmpty);
        }
        if (change == 'effect during prepare' ||
            change == 'available during prepare') {
          final visibility = find.descendant(
              of: find.byType(LevixelSource), matching: find.byType(Opacity));
          expect(tester.widget<Opacity>(visibility).opacity,
              change == 'available during prepare' ? 0 : 1,
              reason: 'Only the reconciled opening source owns visibility');
        }
        var closed = false;
        final closing = controller.close().then((_) => closed = true);
        await pumpNativeWork(tester, () => closed);
        await closing;
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

  for (final effect in [
    'color filter',
    'image filter',
    'shader mask',
    'backdrop filter',
    'rounded clip',
    'superellipse clip',
    'custom rect clip',
    'counter-rotated clip',
    'rounded physical clip',
    'overflowing rounded source',
    'disabled image filter',
    'rectangular physical clip',
  ]) {
    final placements = [
      'child',
      if (['color filter', 'image filter', 'shader mask', 'backdrop filter']
          .contains(effect))
        'ancestor',
    ];
    for (final placement in placements) {
      testWidgets('$placement $effect selects a matching transition',
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
        final controller = LevixelController(galleryId: 'paint', items: [
          LevixelMedia(
              id: 'photo',
              type: LevixelMediaType.image,
              url: 'file:///photo.png')
        ]);
        final supported = effect == 'disabled image filter' ||
            effect == 'rectangular physical clip';
        try {
          final preview =
              RawImage(image: image, width: 100, height: 80, fit: BoxFit.cover);
          final source = LevixelSource(
            controller: controller,
            itemId: 'photo',
            cornerRadius: effect == 'overflowing rounded source' ? 12 : 0,
            child:
                placement == 'child' ? sourcePaint(effect, preview) : preview,
          );
          await tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
                child: placement == 'ancestor'
                    ? sourcePaint(effect, source)
                    : source),
          ));
          await tester.tap(find.byType(LevixelSource));
          await pumpNativeWork(tester, () => opened);
          final prepared = calls
              .singleWhere((call) => call.method == 'prepare')
              .arguments as Map<Object?, Object?>;
          expect(prepared['sourceId'], isNotNull,
              reason: 'Tapping retains the exact preferred source identity');
          expect(prepared['sources'], hasLength(supported ? 1 : 0));
          final visibility = find.descendant(
              of: find.byType(LevixelSource), matching: find.byType(Opacity));
          expect(tester.widget<Opacity>(visibility).opacity, supported ? 0 : 1,
              reason: 'Only a native transition source may hide the thumbnail');
          var closed = false;
          final closing = controller.close().then((_) => closed = true);
          await pumpNativeWork(tester, () => closed);
          await closing;
          expect(tester.widget<Opacity>(visibility).opacity, 1);
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
  }

  for (final change in ['item rebind', 'controller switch', 'style update']) {
    testWidgets('an in-flight source tap respects $change', (tester) async {
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
      var cornerRadius = 0.0;
      late StateSetter rebuild;
      try {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return Center(
              child: LevixelSource(
                key: const ValueKey<String>('source'),
                controller: controller,
                itemId: itemId,
                cornerRadius: cornerRadius,
                child: const SizedBox(width: 100, height: 80),
              ),
            );
          }),
        ));
        final source = find.byKey(const ValueKey<String>('source'));
        final pressed = await tester.startGesture(tester.getCenter(source));
        await tester.pump(const Duration(milliseconds: 150));
        rebuild(() {
          switch (change) {
            case 'item rebind':
              itemId = 'second';
              break;
            case 'controller switch':
              controller = replacement;
              break;
            case 'style update':
              cornerRadius = 12;
              break;
          }
        });
        await tester.pump();
        await pressed.up();
        await tester.pump();
        await tester.pump();
        if (change != 'style update') {
          expect(calls, isEmpty,
              reason: 'An old touch must not open a rebound source');
          await tester.tap(source);
        }
        await pumpNativeWork(tester, () => opened);
        final prepared = calls
            .singleWhere((call) => call.method == 'prepare')
            .arguments as Map<Object?, Object?>;
        final media =
            (prepared['items']! as List<Object?>).cast<Map<Object?, Object?>>();
        expect(prepared['galleryId'], controller.galleryId);
        expect(media[prepared['index']! as int]['id'], itemId);
        expect(calls.where((call) => call.method == 'open'), hasLength(1));
        var closed = false;
        final closing = controller.close().then((_) => closed = true);
        await pumpNativeWork(tester, () => closed);
        await closing;
        expect(tester.takeException(), isNull);
      } finally {
        original.dispose();
        replacement.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

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
        await pumpNativeWork(
            tester,
            () =>
                changed && calls.any((call) => call.method == 'updateSources'));
        ui.Image.onCreate = previousImageCallback;
        expect(changed, isTrue);
        final prepared = calls
            .firstWhere((call) => call.method == 'prepare')
            .arguments as Map<Object?, Object?>;
        final updated = calls
            .lastWhere((call) => call.method == 'updateSources')
            .arguments as Map<Object?, Object?>;
        final sources = (updated['sources']! as List<Object?>)
            .cast<Map<Object?, Object?>>();
        expect(prepared['items']! as List<Object?>, hasLength(2),
            reason: 'The viewer keeps the immutable opening gallery');
        if (change == 'opacity') {
          expect(sources, hasLength(2));
          expect(sources.first['itemId'], 'first');
          expect(sources.first['opacity'], 0.4);
        } else {
          expect(sources.map((source) => source['itemId']), ['second']);
          expect(
              sources
                  .any((source) => source['sourceId'] == prepared['sourceId']),
              isFalse);
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
        return (value['sources']! as List<Object?>)
            .cast<Map<Object?, Object?>>();
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
                const StandardMethodCodec().encodeMethodCall(
                    MethodCall('visibility', <String, Object?>{
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
      expect(sources, hasLength(1),
          reason: 'Only the clicked duplicate blocks presentation');
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
      await pumpNativeWork(
          tester, () => calls.any((call) => call.method == 'updateSources'));
      final updated = calls
          .lastWhere((call) => call.method == 'updateSources')
          .arguments as Map<Object?, Object?>;
      final synchronized =
          (updated['sources']! as List<Object?>).cast<Map<Object?, Object?>>();
      expect(synchronized.map((source) => source['sourceId']).toSet(),
          hasLength(2),
          reason: 'Both duplicates remain return targets');
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
