part of '../levixel.dart';

/// Owns a gallery's current items. An open viewer retains its own immutable copy.
class LevixelController {
  LevixelController({required String galleryId, required Iterable<LevixelMedia> items})
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
  }) => _open(index: index, itemId: itemId, theme: theme, actions: actions,
      actionLayout: actionLayout, actionListIcons: actionListIcons);

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
    final target = itemId == null ? (index ?? 0) : snapshot.indexWhere((item) => item.id == itemId);
    if (target < 0 || target >= snapshot.length) {
      throw RangeError('The requested media is not in this gallery');
    }
    final actionSnapshot = List<LevixelAction>.unmodifiable(actions);
    final ids = <String>{};
    for (final action in actionSnapshot) {
      if (!ids.add(action.id)) throw ArgumentError('Action IDs must be unique');
      if (actionLayout == LevixelActionLayout.grid && action.icon == null) {
        throw ArgumentError('Grid actions require icons');
      }
    }
    final previous = _Bridge.current;
    final session = _Session(this, snapshot, actionSnapshot);
    _Bridge.current = session;
    _Bridge.sessions[session.id] = session;
    try {
      await previous?.close();
      session.checkCurrent();
      await WidgetsBinding.instance.endOfFrame;
      final sources = await session.captureSources();
      session.checkCurrent();
      String? selected = sourceId;
      if (selected == null) {
        for (final source in sources) {
          if (source['itemId'] == snapshot[target].id) { selected = source['sourceId']! as String; break; }
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
      if (selected != null) _sources[selected]?._setHidden(session.id, true);
      await WidgetsBinding.instance.endOfFrame;
      session.checkCurrent();
      await _Bridge.channel.invokeMethod<void>('open', session.arguments);
      session.checkCurrent();
      session.watchFrames();
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  /// Completes after native dismissal and thumbnail restoration.
  Future<void> close() async {
    final session = _Bridge.current;
    if (session?.controller == this) await session!.close();
  }

  Future<bool> retry() async {
    _checkAlive();
    final session = _Bridge.current;
    if (session?.controller != this || session!.closing) return false;
    return await _Bridge.channel.invokeMethod<bool>('retry', session.arguments) ?? false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close().catchError(_Bridge.report));
    unawaited(_events.close());
  }

  void _checkAlive() {
    if (_disposed) throw StateError('LevixelController has been disposed');
  }
}

class _Bridge {
  static const channel = MethodChannel('com.sandrox.levixel/flutter');
  static bool _initialized = false;
  static int nextId = 0;
  static _Session? current;
  static final sessions = <String, _Session>{};

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      final value = (call.arguments! as Map<Object?, Object?>);
      final session = sessions[value['requestId']];
      if (session == null) return;
      if (call.method == 'visibility') {
        final source = session.controller._sources[value['sourceId']];
        final hidden = value['hidden']! as bool;
        if (!hidden || !session.closing) source?._setHidden(session.id, hidden);
        await WidgetsBinding.instance.endOfFrame;
      } else if (call.method == 'event') {
        final event = LevixelEvent._(value);
        if (!session.controller._disposed) session.controller._events.add(event);
        if (event.type == LevixelEventType.action && !session.controller._disposed) {
          for (final action in session.actions) {
            if (action.id == event.actionId && !action.disabled) {
              try { action.onSelected?.call(event); } catch (error, stack) { report(error, stack); }
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

  static void report(Object error, [StackTrace? stack]) {
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'levixel'));
  }
}

class _Session {
  _Session(this.controller, this.items, this.actions) : id = 'flutter-${++_Bridge.nextId}';
  final String id;
  final LevixelController controller;
  final List<LevixelMedia> items;
  final List<LevixelAction> actions;
  bool prepared = false;
  bool closing = false;
  bool _syncing = false;
  Future<void>? _closeFuture;
  Future<void>? _finishFuture;
  Map<String, String> _sentSignatures = <String, String>{};
  Map<String, int> _sentImages = <String, int>{};
  Map<String, Object?> get arguments => <String, Object?>{'requestId': id};

  void checkCurrent() {
    if (closing || controller._disposed || _Bridge.current != this) {
      throw PlatformException(code: 'OPEN_CANCELLED', message: 'The open request was replaced or closed');
    }
  }

  Future<List<Map<String, Object?>>> captureSources() async {
    final allowed = items.map((item) => item.id).toSet();
    final mounted = controller.items.map((item) => item.id).toSet();
    final result = <Map<String, Object?>>[];
    for (final source in controller._sources.values.toList()) {
      if (!allowed.contains(source.widget.itemId) || !mounted.contains(source.widget.itemId)) continue;
      final value = await source._capture();
      if (value != null && controller._sources[value['sourceId']] == source) result.add(value);
    }
    return result;
  }

  void watchFrames() {
    if (closing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (closing) return;
      if (!_syncing) unawaited(syncSources().catchError(_Bridge.report));
      watchFrames();
    });
  }

  Future<void> syncSources() async {
    if (closing || !prepared || _syncing) return;
    _syncing = true;
    try {
      final sources = await captureSources();
      if (closing) return;
      final signatures = <String, String>{
        for (final source in sources) source['sourceId']! as String: source['signature']! as String,
      };
      if (mapEquals(signatures, _sentSignatures)) return;
      for (final source in sources) {
        if (_sentImages[source['sourceId']] == source['imageVersion']) source.remove('png');
      }
      await _Bridge.channel.invokeMethod<void>('updateSources', <String, Object?>{...arguments, 'sources': sources});
      _sentSignatures = signatures;
      _sentImages = <String, int>{for (final source in sources) source['sourceId']! as String: source['imageVersion']! as int};
    } finally { _syncing = false; }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    closing = true;
    try {
      if (prepared) {
        try {
          await WidgetsBinding.instance.endOfFrame;
          final sources = await captureSources();
          await _Bridge.channel.invokeMethod<void>('updateSources', <String, Object?>{...arguments, 'sources': sources});
        } finally {
          await _Bridge.channel.invokeMethod<void>('close', arguments);
        }
      }
    } finally { await finish(); }
  }

  Future<void> finish() => _finishFuture ??= _finish();
  Future<void> _finish() async {
    closing = true;
    for (final source in controller._sources.values.toList()) { source._setHidden(id, false); }
    await WidgetsBinding.instance.endOfFrame;
    try {
      if (prepared) await _Bridge.channel.invokeMethod<void>('finish', arguments);
    } finally {
      for (final source in controller._sources.values) { source._releasePreview(); }
      _Bridge.sessions.remove(id);
      if (_Bridge.current == this) _Bridge.current = null;
    }
  }
}
