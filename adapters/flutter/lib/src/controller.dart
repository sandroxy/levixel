part of '../levixel.dart';

/// Owns a gallery's current items. An open viewer retains its own immutable copy.
class LevixelController {
  LevixelController(
      {required String galleryId, required Iterable<LevixelMedia> items})
      : galleryId = _nonEmpty(galleryId, 'galleryId'),
        _items = _mediaSnapshot(items) {
    _Bridge.initialize();
  }

  final String galleryId;
  List<LevixelMedia> _items;
  final _sources = <String, _LevixelSourceState>{};
  final _events = StreamController<LevixelEvent>.broadcast();
  bool _disposed = false;

  List<LevixelMedia> get items => _items;
  set items(Iterable<LevixelMedia> value) {
    _checkAlive();
    _items = _mediaSnapshot(value);
    WidgetsBinding.instance.scheduleFrame();
  }

  Stream<LevixelEvent> get events => _events.stream;

  Future<void> open({
    int? index,
    String? itemId,
    LevixelTheme theme = LevixelTheme.dark,
    Iterable<LevixelAction> actions = const <LevixelAction>[],
    LevixelActionLayout actionLayout = LevixelActionLayout.list,
    bool actionListIcons = false,
  }) =>
      _open(
          index: index,
          itemId: itemId,
          theme: theme,
          actions: actions,
          actionLayout: actionLayout,
          actionListIcons: actionListIcons);

  Future<void> _open({
    int? index,
    String? itemId,
    String? sourceId,
    LevixelTheme theme = LevixelTheme.dark,
    Iterable<LevixelAction> actions = const <LevixelAction>[],
    LevixelActionLayout actionLayout = LevixelActionLayout.list,
    bool actionListIcons = false,
  }) async {
    _checkAlive();
    if (index != null && itemId != null) {
      throw ArgumentError('Specify either index or itemId');
    }
    final snapshot = _items;
    final target = itemId == null
        ? (index ?? 0)
        : snapshot.indexWhere((item) => item.id == itemId);
    if (target < 0 || target >= snapshot.length) {
      throw RangeError('The requested media is not in this gallery');
    }
    final actionSnapshot = List<LevixelAction>.unmodifiable(actions);
    final ids = <String>{};
    for (final action in actionSnapshot) {
      if (!ids.add(action.id)) {
        throw ArgumentError('Action IDs must be unique');
      }
      if (actionLayout == LevixelActionLayout.grid && action.icon == null) {
        throw ArgumentError('Grid actions require icons');
      }
    }
    final previous = _Bridge.current;
    final session = _Session(this, snapshot, actionSnapshot, previous?.close());
    _Bridge.current = session;
    _Bridge.sessions[session.id] = session;
    try {
      await session.previousClose;
      session.checkCurrent();
      await _Bridge.pendingFrame();
      session.checkCurrent();
      final sources = await session.captureSources(
          openingItemId: snapshot[target].id, preferredSourceId: sourceId);
      session.checkCurrent();
      String? selected = sourceId;
      if (selected == null) {
        for (final source in sources) {
          if (source['itemId'] == snapshot[target].id) {
            selected = source['sourceId']! as String;
            break;
          }
        }
      }
      session.prepared = true;
      await _Bridge.channel.invokeMethod<void>('prepare', <String, Object?>{
        'requestId': session.id,
        'galleryId': galleryId,
        'items': snapshot.map((item) => item._toMap()).toList(),
        'index': target,
        'sourceId': selected,
        'sources': sources,
        'theme': theme.name,
        'actions': actionSnapshot.map((action) => action._toMap()).toList(),
        'actionLayout': actionLayout.name,
        'actionListIcons': actionListIcons,
      });
      session.checkCurrent();
      session.rememberSources(sources);
      final hiddenSource = selected != null && session.hasSource(selected)
          ? _sources[selected]
          : null;
      hiddenSource?._setHidden(session.id, true);
      await _Bridge.nextFrame();
      session.checkCurrent();
      // Preparation and the Flutter handoff frame can change source geometry
      // or eligibility. Reconcile the anchors before native presentation.
      await session.syncSources(
          openingItemId: snapshot[target].id, preferredSourceId: selected);
      session.checkCurrent();
      final openingSource = selected != null && session.hasSource(selected)
          ? _sources[selected]
          : null;
      if (hiddenSource != openingSource) {
        hiddenSource?._setHidden(session.id, false);
        openingSource?._setHidden(session.id, true);
        await _Bridge.nextFrame();
        session.checkCurrent();
      }
      await _Bridge.channel.invokeMethod<void>('open', session.arguments);
      session.checkCurrent();
      session.watchFrames();
      WidgetsBinding.instance.scheduleFrame();
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  /// Completes after native dismissal and thumbnail restoration.
  Future<void> close() async {
    final session = _Bridge.current;
    if (session?.controller == this) {
      await session!.close();
    }
  }

  Future<bool> retry() async {
    _checkAlive();
    final session = _Bridge.current;
    if (session?.controller != this || session!.closing) {
      return false;
    }
    return await _Bridge.channel
            .invokeMethod<bool>('retry', session.arguments) ??
        false;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(close().catchError(_Bridge.report));
    unawaited(_events.close());
  }

  void _checkAlive() {
    if (_disposed) {
      throw StateError('LevixelController has been disposed');
    }
  }
}

class _Bridge {
  static const channel = MethodChannel('com.sandrox.levixel/flutter');
  static bool _initialized = false;
  static int nextId = 0;
  static _Session? current;
  static final sessions = <String, _Session>{};

  static void initialize() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      final value = (call.arguments! as Map<Object?, Object?>);
      final session = sessions[value['requestId']];
      if (session == null) {
        return;
      }
      if (call.method == 'visibility') {
        final source = session.controller._sources[value['sourceId']];
        final hidden = value['hidden']! as bool;
        if (!hidden || !session.closing) {
          source?._setHidden(session.id, hidden);
        }
        await nextFrame();
      } else if (call.method == 'event') {
        final event = LevixelEvent._(value);
        if (!session.controller._disposed) {
          session.controller._events.add(event);
        }
        if (event.type == LevixelEventType.action &&
            !session.controller._disposed) {
          for (final action in session.actions) {
            if (action.id == event.actionId && !action.disabled) {
              try {
                action.onSelected?.call(event);
              } catch (error, stack) {
                report(error, stack);
              }
              break;
            }
          }
        }
        if (event.type == LevixelEventType.dismiss) {
          unawaited(session.finish().catchError(report));
        }
      }
    });
  }

  static void reportOpenFailure(Object error, [StackTrace? stack]) {
    if (error is PlatformException && error.code == 'OPEN_CANCELLED') {
      return;
    }
    report(error, stack);
  }

  static Future<void> nextFrame() async {
    final binding = WidgetsBinding.instance;
    if (!binding.framesEnabled) {
      return;
    }
    final waiter = _FrameWaiter();
    binding.addObserver(waiter);
    try {
      unawaited(binding.endOfFrame.then((_) => waiter.complete()));
      await waiter.done.future;
    } finally {
      binding.removeObserver(waiter);
    }
  }

  static Future<void> pendingFrame() async {
    final binding = WidgetsBinding.instance;
    if (binding.hasScheduledFrame ||
        (binding.schedulerPhase != SchedulerPhase.idle &&
            binding.schedulerPhase != SchedulerPhase.postFrameCallbacks)) {
      await nextFrame();
    }
  }

  static void report(Object error, [StackTrace? stack]) {
    FlutterError.reportError(FlutterErrorDetails(
        exception: error, stack: stack, library: 'levixel'));
  }
}

class _FrameWaiter with WidgetsBindingObserver {
  final done = Completer<void>();

  void complete() {
    if (!done.isCompleted) {
      done.complete();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!WidgetsBinding.instance.framesEnabled) {
      complete();
    }
  }
}

class _Session {
  _Session(this.controller, this.items, this.actions, this.previousClose)
      : id = 'flutter-${++_Bridge.nextId}';
  final String id;
  final LevixelController controller;
  final List<LevixelMedia> items;
  final List<LevixelAction> actions;
  final Future<void>? previousClose;
  bool prepared = false;
  bool closing = false;
  bool _syncing = false;
  Future<void>? _closeFuture;
  Future<void>? _finishFuture;
  Map<String, String> _sentSignatures = <String, String>{};
  Map<String, int> _sentImages = <String, int>{};
  Map<String, Object?> get arguments => <String, Object?>{'requestId': id};

  bool hasSource(String sourceId) => _sentSignatures.containsKey(sourceId);

  void rememberSources(List<Map<String, Object?>> sources) {
    _sentSignatures = <String, String>{
      for (final source in sources)
        source['sourceId']! as String: source['signature']! as String,
    };
    _sentImages = <String, int>{
      for (final source in sources)
        source['sourceId']! as String: source['imageVersion']! as int,
    };
  }

  void checkCurrent() {
    if (closing ||
        controller._disposed ||
        _Bridge.current != this ||
        !WidgetsBinding.instance.framesEnabled) {
      throw PlatformException(
          code: 'OPEN_CANCELLED',
          message: 'The open request was replaced, closed, or suspended');
    }
  }

  Future<List<Map<String, Object?>>> captureSources(
      {String? openingItemId, String? preferredSourceId}) async {
    final allowed = items.map((item) => item.id).toSet();
    for (final source in controller._sources.values.toList()) {
      if (!allowed.contains(source.widget.itemId) ||
          !controller.items.any((item) => item.id == source.widget.itemId)) {
        continue;
      }
      if (openingItemId != null &&
          (source.widget.itemId != openingItemId ||
              (preferredSourceId != null &&
                  source._sourceId != preferredSourceId))) {
        continue;
      }
      final captured = await source._capture();
      // Presentation needs only its selected thumbnail. Other mounted sources
      // are synchronized after opening, without blocking the tap on their PNGs.
      if (openingItemId != null && captured != null) {
        break;
      }
    }
    // Encoding another thumbnail can yield to removal, rebinding or repainting
    // of an earlier one. Sample the complete batch without further encoding.
    final mounted = controller.items.map((item) => item.id).toSet();
    final sources = controller._sources.values.toList();
    final snapshots = await Future.wait([
      for (final source in sources)
        if (allowed.contains(source.widget.itemId) &&
            mounted.contains(source.widget.itemId))
          source._capture(allowEncoding: false),
    ]);
    return [
      for (final value in snapshots)
        if (value != null &&
            controller._sources[value['sourceId']]?.widget.itemId ==
                value['itemId'] &&
            controller.items.any((item) => item.id == value['itemId']))
          value,
    ];
  }

  void watchFrames() {
    if (closing) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (closing) {
        return;
      }
      if (!_syncing) {
        unawaited(syncSources().catchError(_Bridge.report));
      }
      watchFrames();
    });
  }

  Future<void> syncSources(
      {String? openingItemId, String? preferredSourceId}) async {
    if (closing || !prepared || _syncing) {
      return;
    }
    _syncing = true;
    try {
      final sources = await captureSources(
          openingItemId: openingItemId, preferredSourceId: preferredSourceId);
      if (closing) {
        return;
      }
      final signatures = <String, String>{
        for (final source in sources)
          source['sourceId']! as String: source['signature']! as String,
      };
      if (mapEquals(signatures, _sentSignatures)) {
        return;
      }
      for (final source in sources) {
        if (_sentImages[source['sourceId']] == source['imageVersion']) {
          source.remove('png');
        }
      }
      await _Bridge.channel.invokeMethod<void>(
          'updateSources', <String, Object?>{...arguments, 'sources': sources});
      rememberSources(sources);
    } finally {
      _syncing = false;
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    closing = true;
    try {
      // A canceled opening still owns the wait for the preceding native viewer.
      // Its replacement must wait until that viewer has finished closing.
      await previousClose;
      if (prepared) {
        try {
          await _Bridge.nextFrame();
          if (WidgetsBinding.instance.framesEnabled) {
            final sources = await captureSources();
            await _Bridge.channel.invokeMethod<void>('updateSources',
                <String, Object?>{...arguments, 'sources': sources});
          }
        } finally {
          await _Bridge.channel.invokeMethod<void>('close', <String, Object?>{
            ...arguments,
            'animated': WidgetsBinding.instance.framesEnabled,
          });
        }
      }
    } finally {
      await finish();
    }
  }

  Future<void> finish() => _finishFuture ??= _finish();
  Future<void> _finish() async {
    closing = true;
    for (final source in controller._sources.values.toList()) {
      source._setHidden(id, false);
    }
    await _Bridge.nextFrame();
    try {
      if (prepared) {
        await _Bridge.channel.invokeMethod<void>('finish', arguments);
      }
    } finally {
      _Bridge.sessions.remove(id);
      if (_Bridge.current == this) {
        _Bridge.current = null;
      }
    }
  }
}
