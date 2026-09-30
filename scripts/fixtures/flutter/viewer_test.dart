import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:levixel_source_host/main.dart' as app;
import 'package:sandrox_levixel/levixel.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'native sessions preserve identity and restore Flutter thumbnails',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle();
      final host = tester.state<app.ViewerHarnessState>(
        find.byType(app.ViewerHarness),
      );
      final events = <LevixelEvent>[];
      final subscription = host.controller.events.listen(events.add);
      final firstSource = find.byKey(const ValueKey<String>('first'));
      final opacity = find.descendant(
        of: firstSource,
        matching: find.byType(Opacity),
      );
      await tester.runAsync(() async {
        final opened = host.controller.events.firstWhere(
          (event) => event.type == LevixelEventType.opened,
        );
        final loaded = host.controller.events.firstWhere(
          (event) =>
              event.type == LevixelEventType.mediaLoad &&
              event.itemId == 'first',
        );
        await tester.tap(firstSource);
        await Future.wait([opened, loaded])
            .timeout(const Duration(seconds: 20));
        expect(tester.widget<Opacity>(opacity).opacity, 0);
        host.reverseItems();
        await binding.endOfFrame;
        final dismissed = host.controller.events.firstWhere(
          (event) => event.type == LevixelEventType.dismiss,
        );
        await host.controller.close();
        final event = await dismissed.timeout(const Duration(seconds: 10));
        expect(event.itemId, 'first');
        expect(
          event.index,
          0,
          reason: 'Dismissal uses the opening snapshot, not the reordered host list',
        );
        expect(event.galleryId, 'source-test');
      });
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(
        events.where((event) => event.type == LevixelEventType.dismiss).length,
        1,
      );
      final initialIndex = events.indexWhere(
        (event) => event.type == LevixelEventType.indexChange,
      );
      final initialOpen = events.indexWhere(
        (event) => event.type == LevixelEventType.opened,
      );
      expect(initialIndex, greaterThanOrEqualTo(0));
      expect(initialIndex, lessThan(initialOpen));

      await tester.runAsync(() async {
        final opened = host.controller.events.firstWhere(
          (event) => event.type == LevixelEventType.opened,
        );
        await host.controller.open(itemId: 'first');
        await opened.timeout(const Duration(seconds: 20));
        host.removeSources();
        await binding.endOfFrame;
        final dismissed = host.controller.events.firstWhere(
          (event) => event.type == LevixelEventType.dismiss,
        );
        await host.controller.close();
        expect(
          (await dismissed.timeout(const Duration(seconds: 10))).itemId,
          'first',
        );
      });
      await tester.pumpAndSettle();
      expect(find.byType(LevixelSource), findsNothing);
      expect(
        events.where((event) => event.type == LevixelEventType.dismiss).length,
        2,
      );
      await subscription.cancel();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
