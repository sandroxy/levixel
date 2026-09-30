import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sandrox_levixel/levixel.dart';

const channel = MethodChannel('com.sandrox.levixel/flutter');
const codec = StandardMethodCodec();

LevixelMedia media(String id) =>
    LevixelMedia(id: id, type: LevixelMediaType.image, url: 'file:///$id.png');

Future<void> settle(WidgetTester tester, Future<void> future) async {
  Object? error;
  bool complete = false;
  unawaited(future.then((_) {
    complete = true;
  }, onError: (Object value) {
    error = value;
    complete = true;
  }));
  for (var i = 0; i < 30 && !complete; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(complete, isTrue,
      reason: 'The operation must settle without an arbitrary native timeout');
  if (error != null) {
    throw error!;
  }
}

Future<void> nativeEvent(WidgetTester tester, String request, String type,
    {String? actionId, num time = 1}) async {
  final response = tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('event', <String, Object?>{
        'requestId': request,
        'type': type,
        'time': time,
        'payload': <String, Object?>{
          'sessionId': 'native-session',
          'galleryId': 'gallery',
          'index': 0,
          'itemId': 'first',
          'mediaType': 'image',
          if (actionId != null) 'actionId': actionId,
        },
      })),
      null);
  await settle(tester, response.then((_) {}));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'retry' ? true : null;
    });
  });

  testWidgets('rejects invalid requests before native side effects',
      (tester) async {
    expect(
        () => LevixelController(
            galleryId: 'gallery', items: [media('same'), media('same')]),
        throwsArgumentError);
    final controller = LevixelController(galleryId: 'gallery', items: []);
    await expectLater(controller.open(), throwsRangeError);
    controller.items = [media('first')];
    await expectLater(
        controller.open(index: 0, itemId: 'first'), throwsArgumentError);
    await expectLater(
        controller.open(
            actions: [LevixelAction(id: 'save', label: 'Save')],
            actionLayout: LevixelActionLayout.grid),
        throwsArgumentError);
    expect(calls, isEmpty);
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('media and callbacks retain the opening snapshot',
      (tester) async {
    final input = [media('first'), media('second')];
    final controller = LevixelController(galleryId: 'gallery', items: input);
    final selected = <String>[];
    final actions = [
      LevixelAction(
          id: 'save',
          label: 'Save',
          onSelected: (event) => selected.add(event.itemId))
    ];
    input.clear();
    await settle(tester, controller.open(actions: actions));
    final prepared = (calls
        .firstWhere((call) => call.method == 'prepare')
        .arguments as Map<Object?, Object?>);
    final request = prepared['requestId']! as String;
    actions.clear();
    controller.items = [media('second'), media('first')];
    expect((prepared['items']! as List<Object?>).length, 2);
    await nativeEvent(tester, request, 'action', actionId: 'save', time: 1.0);
    expect(selected, ['first']);
    await settle(tester, controller.close());
    await nativeEvent(tester, request, 'action', actionId: 'save');
    expect(selected, ['first'],
        reason: 'Events after dismissal must not reuse callbacks');
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('close awaits native dismissal and shares one completion',
      (tester) async {
    final controller =
        LevixelController(galleryId: 'gallery', items: [media('first')]);
    await settle(tester, controller.open());
    final dismissal = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'close') {
        await dismissal.future;
      }
      return null;
    });
    var completed = 0;
    final first = controller.close().then((_) {
      completed++;
    });
    final second = controller.close().then((_) {
      completed++;
    });
    await tester.pump();
    await tester.pump();
    expect(completed, 0);
    expect(calls.where((call) => call.method == 'close').length, 1);
    dismissal.complete();
    await settle(tester, Future.wait([first, second]).then((_) {}));
    expect(completed, 2);
    expect(calls.where((call) => call.method == 'finish').length, 1);
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a close during preparation cancels the delayed open',
      (tester) async {
    final controller =
        LevixelController(galleryId: 'gallery', items: [media('first')]);
    final preparation = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'prepare') {
        await preparation.future;
      }
      return null;
    });
    Object? failure;
    final opening = controller.open().catchError((Object error) {
      failure = error;
    });
    await tester.pump();
    await tester.pump();
    final closing = controller.close();
    preparation.complete();
    await settle(tester, Future.wait([opening, closing]).then((_) {}));
    expect(
        failure,
        isA<PlatformException>()
            .having((error) => error.code, 'code', 'OPEN_CANCELLED'));
    expect(calls.where((call) => call.method == 'open'), isEmpty);
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('a source update failure still dismisses the viewer',
      (tester) async {
    final controller =
        LevixelController(galleryId: 'gallery', items: [media('first')]);
    await settle(tester, controller.open());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'updateSources') {
        throw PlatformException(code: 'INVALID_ARGUMENT');
      }
      return null;
    });
    Object? failure;
    await settle(
        tester,
        controller.close().catchError((Object error) {
          failure = error;
        }));
    expect(failure, isA<PlatformException>());
    expect(calls.where((call) => call.method == 'close').length, 1);
    expect(calls.where((call) => call.method == 'finish').length, 1);
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('one controller cannot close another gallery', (tester) async {
    final first =
        LevixelController(galleryId: 'first-gallery', items: [media('first')]);
    final second = LevixelController(
        galleryId: 'second-gallery', items: [media('second')]);
    await settle(tester, first.open());
    await settle(tester, second.open());
    final closes = calls.where((call) => call.method == 'close').length;
    await first.close();
    expect(calls.where((call) => call.method == 'close').length, closes);
    await settle(tester, second.close());
    first.dispose();
    second.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('disposing settles an active viewer without later callbacks',
      (tester) async {
    final controller =
        LevixelController(galleryId: 'gallery', items: [media('first')]);
    await settle(tester, controller.open());
    controller.dispose();
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(calls.where((call) => call.method == 'close').length, 1);
    expect(calls.where((call) => call.method == 'finish').length, 1);
    expect(() => controller.items = [media('second')], throwsStateError);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
