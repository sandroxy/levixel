part of '../levixel.dart';

/// A Flutter thumbnail registered by stable media identity.
///
/// The child remains a Flutter widget. Shared transitions use its decoded image,
/// layout, clipping, and uniform [cornerRadius]. Unsupported image effects or
/// unavailable geometry use the native viewer's fade transition.
class LevixelSource extends StatefulWidget {
  const LevixelSource({
    super.key,
    required this.controller,
    required this.itemId,
    required this.child,
    this.cornerRadius = 0,
    this.theme = LevixelTheme.dark,
    this.actions = const <LevixelAction>[],
    this.actionLayout = LevixelActionLayout.list,
    this.actionListIcons = false,
  });

  final LevixelController controller;
  final String itemId;
  final Widget child;
  final double cornerRadius;
  final LevixelTheme theme;
  final List<LevixelAction> actions;
  final LevixelActionLayout actionLayout;
  final bool actionListIcons;

  @override
  State<LevixelSource> createState() => _LevixelSourceState();
}

class _LevixelSourceState extends State<LevixelSource> {
  final _contentKey = GlobalKey();
  final _opacityKey = GlobalKey();
  final _hiddenBy = <String>{};
  late String _sourceId;
  ui.Image? _encodedImage;
  Uint8List? _png;
  int _imageVersion = 0;

  @override
  void initState() {
    super.initState();
    _register();
  }

  void _register() {
    _nonEmpty(widget.itemId, 'itemId');
    widget.controller._checkAlive();
    if (!widget.cornerRadius.isFinite || widget.cornerRadius < 0) {
      throw ArgumentError.value(widget.cornerRadius, 'cornerRadius',
          'Must be finite and non-negative');
    }
    _sourceId = 'source-${++_Bridge.nextId}';
    widget.controller._sources[_sourceId] = this;
  }

  @override
  void didUpdateWidget(LevixelSource oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.itemId != widget.itemId) {
      oldWidget.controller._sources.remove(_sourceId);
      _hiddenBy.clear();
      _encodedImage = null;
      _png = null;
      _register();
    }
    if (!widget.cornerRadius.isFinite || widget.cornerRadius < 0) {
      throw ArgumentError.value(widget.cornerRadius, 'cornerRadius');
    }
  }

  @override
  void dispose() {
    widget.controller._sources.remove(_sourceId);
    _png = null;
    super.dispose();
  }

  void _setHidden(String requestId, bool hidden) {
    if (!mounted) {
      return;
    }
    final changed =
        hidden ? _hiddenBy.add(requestId) : _hiddenBy.remove(requestId);
    if (changed) {
      setState(() {});
    }
  }

  void _releasePreview() {
    _encodedImage = null;
    _png = null;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(widget.controller
            ._open(
              itemId: widget.itemId,
              sourceId: _sourceId,
              theme: widget.theme,
              actions: widget.actions,
              actionLayout: widget.actionLayout,
              actionListIcons: widget.actionListIcons,
            )
            .catchError(_Bridge.report)),
        child: Opacity(
          key: _opacityKey,
          opacity: _hiddenBy.isEmpty ? 1 : 0,
          child: RepaintBoundary(
            key: _contentKey,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.cornerRadius),
                child: widget.child),
          ),
        ),
      );

  Future<Map<String, Object?>?> _capture() async {
    if (!mounted) {
      return null;
    }
    final sourceId = _sourceId;
    final root = _contentKey.currentContext?.findRenderObject();
    if (root == null || !root.attached) {
      return null;
    }
    final images = <RenderImage>[];
    void visit(RenderObject object) {
      if (object is RenderOffstage && object.offstage) {
        return;
      }
      if (object is RenderOpacity && object.opacity < 0.999) {
        return;
      }
      if (object is RenderAnimatedOpacity && object.opacity.value < 0.999) {
        return;
      }
      if (object is RenderClipPath || object is RenderClipOval) {
        return;
      }
      if (object is RenderImage && object.image != null) {
        images.add(object);
      }
      object.visitChildren(visit);
    }

    visit(root);
    if (images.length != 1) {
      return null;
    }
    final render = images.single;
    final image = render.image;
    if (image == null ||
        !render.hasSize ||
        render.size.isEmpty ||
        render.color != null ||
        render.invertColors ||
        render.centerSlice != null ||
        render.matchTextDirection ||
        render.repeat != ImageRepeat.noRepeat ||
        (render.opacity?.value ?? 1) < 0.999 ||
        render.alignment.resolve(render.textDirection) != Alignment.center) {
      return null;
    }
    var fit = render.fit ?? BoxFit.scaleDown;
    if (fit == BoxFit.scaleDown &&
        (render.size.width <= image.width / render.scale ||
            render.size.height <= image.height / render.scale)) {
      fit = BoxFit.contain;
    }
    if (fit != BoxFit.cover && fit != BoxFit.contain && fit != BoxFit.fill) {
      return null;
    }
    final transform = render.getTransformTo(null);
    final m = transform.storage;
    if (m[0] <= 0 ||
        m[5] <= 0 ||
        (m[0] - m[5]).abs() > 0.0001 ||
        m[1].abs() > 0.0001 ||
        m[4].abs() > 0.0001 ||
        m[3].abs() > 0.0001 ||
        m[7].abs() > 0.0001 ||
        (m[15] - 1).abs() > 0.0001) {
      return null;
    }
    final frame =
        MatrixUtils.transformRect(transform, Offset.zero & render.size);
    final view = View.of(context);
    var clip = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    RenderObject child = render;
    while (child.parent != null) {
      final parent = child.parent!;
      if (parent is RenderOffstage && parent.offstage) {
        return null;
      }
      if (parent is RenderOpacity &&
          parent != _opacityKey.currentContext?.findRenderObject() &&
          parent.opacity < 0.999) {
        return null;
      }
      if (parent is RenderAnimatedOpacity && parent.opacity.value < 0.999) {
        return null;
      }
      if (parent is RenderClipPath || parent is RenderClipOval) {
        return null;
      }
      final bounds = parent.describeApproximatePaintClip(child);
      if (bounds != null) {
        clip = clip.intersect(
            MatrixUtils.transformRect(parent.getTransformTo(null), bounds));
      }
      child = parent;
    }
    clip = clip.intersect(frame);
    if (clip.isEmpty || !frame.isFinite || !clip.isFinite) {
      return null;
    }
    if (_encodedImage != image || _png == null) {
      final retained = image.clone();
      ui.Image? preview;
      ui.Picture? picture;
      try {
        final longest = math.max(image.width, image.height);
        final previewSide = math.min(1024,
            math.max(frame.width, frame.height) * view.devicePixelRatio * 2);
        final ratio = math.min(1.0, previewSide / longest);
        final width = math.max(1, (image.width * ratio).round());
        final height = math.max(1, (image.height * ratio).round());
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
            retained,
            ui.Rect.fromLTWH(
                0, 0, retained.width.toDouble(), retained.height.toDouble()),
            ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.medium);
        picture = recorder.endRecording();
        preview = await picture.toImage(width, height);
        final data = await preview.toByteData(format: ui.ImageByteFormat.png);
        if (!mounted ||
            _sourceId != sourceId ||
            render.image != image ||
            data == null) {
          return null;
        }
        _encodedImage = image;
        _png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        _imageVersion++;
      } finally {
        preview?.dispose();
        picture?.dispose();
        retained.dispose();
      }
    }
    if (!mounted || _sourceId != sourceId || !render.attached) {
      return null;
    }
    // Encoding is asynchronous; changed geometry belongs to the next snapshot.
    if (MatrixUtils.transformRect(
            render.getTransformTo(null), Offset.zero & render.size) !=
        frame) {
      return null;
    }
    final container = root is RenderBox
        ? MatrixUtils.transformRect(
            root.getTransformTo(null), Offset.zero & root.size)
        : frame;
    final radius =
        container == frame ? widget.cornerRadius * math.min(m[0], m[5]) : 0.0;
    final signature =
        '$sourceId:${widget.itemId}:$frame:$clip:$radius:$fit:$_imageVersion:${view.devicePixelRatio}';
    return <String, Object?>{
      'sourceId': sourceId,
      'itemId': widget.itemId,
      'frame': <double>[frame.left, frame.top, frame.width, frame.height],
      'clip': <double>[clip.left, clip.top, clip.width, clip.height],
      'cornerRadius': radius,
      'pixelRatio': view.devicePixelRatio,
      'fit': fit.name,
      'png': _png,
      'imageVersion': _imageVersion,
      'signature': signature,
    };
  }
}
