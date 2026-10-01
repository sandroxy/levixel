import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sandrox_levixel/levixel.dart';

import 'main.dart' show createMediaFiles;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(home: GestureHarness(files: await createMediaFiles())));
}

class GestureHarness extends StatefulWidget {
  const GestureHarness({super.key, required this.files});
  final List<File> files;

  @override
  State<GestureHarness> createState() => _GestureHarnessState();
}

class _GestureHarnessState extends State<GestureHarness> {
  late final LevixelController _controller;
  late final StreamSubscription<LevixelEvent> _subscription;
  var _dismissCount = 0;
  var _dismiss = 'Dismiss 0';
  var _action = 'Action none';

  @override
  void initState() {
    super.initState();
    _controller = LevixelController(
      galleryId: 'gesture-test',
      items: [
        for (var index = 0; index < widget.files.length; index++)
          LevixelMedia(
            id: index == 0 ? 'first' : 'second',
            type: LevixelMediaType.image,
            url: widget.files[index].uri.toString(),
          ),
      ],
    );
    _subscription = _controller.events.listen((event) {
      if (event.type == LevixelEventType.dismiss && mounted) {
        setState(() {
          _dismissCount++;
          _dismiss = 'Dismiss $_dismissCount ${event.itemId} ${event.index}';
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Levixel gesture checks')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 24,
            children: [
              for (final item in _controller.items)
                Semantics(
                  identifier: 'source-${item.id}',
                  label: 'Open ${item.id}',
                  button: true,
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: LevixelSource(
                      controller: _controller,
                      itemId: item.id,
                      cornerRadius: 12,
                      actions: [
                        LevixelAction(
                          id: 'inspect',
                          label: 'Inspect',
                          onSelected: (event) => setState(() {
                            _action =
                                'Action inspect '
                                '${event.itemId} ${event.index}';
                          }),
                        ),
                      ],
                      child: Image.file(
                        File.fromUri(Uri.parse(item.url)),
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Semantics(
            identifier: 'events',
            label: '$_dismiss | $_action',
            excludeSemantics: true,
            child: Text('$_dismiss | $_action'),
          ),
        ],
      ),
    ),
  );
}
