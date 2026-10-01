import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sandrox_levixel/levixel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(home: ViewerHarness(files: await createMediaFiles())));
}

Future<List<File>> createMediaFiles() async {
  final directory = await Directory.systemTemp.createTemp(
    'levixel-source-test-',
  );
  final images = <String>[
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAIAAADkharWAAAAFUlEQVR4nGO4ZO5GEmIY1TCqATsCAAe7+0HCr1XQAAAAAElFTkSuQmCC',
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAIAAADkharWAAAAFUlEQVR4nGOQq7hEEmIY1TCqATsCAKFnDhADijAjAAAAAElFTkSuQmCC',
  ];
  final files = <File>[];
  for (var i = 0; i < images.length; i++) {
    files.add(
      await File('${directory.path}/$i.png')
          .writeAsBytes(base64Decode(images[i])),
    );
  }
  return files;
}

class ViewerHarness extends StatefulWidget {
  const ViewerHarness({super.key, required this.files});
  final List<File> files;
  @override
  State<ViewerHarness> createState() => ViewerHarnessState();
}

class ViewerHarnessState extends State<ViewerHarness> {
  late final LevixelController controller;
  late List<LevixelMedia> items;

  @override
  void initState() {
    super.initState();
    items = <LevixelMedia>[
      LevixelMedia(
        id: 'first',
        type: LevixelMediaType.image,
        url: widget.files[0].uri.toString(),
      ),
      LevixelMedia(
        id: 'second',
        type: LevixelMediaType.image,
        url: widget.files[1].uri.toString(),
      ),
    ];
    controller = LevixelController(galleryId: 'source-test', items: items);
  }

  void reverseItems() => setState(() {
    items = items.reversed.toList();
    controller.items = items;
  });
  void removeSources() => setState(() {
    items = <LevixelMedia>[];
    controller.items = items;
  });

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Levixel source checks')),
    body: Center(
      child: Wrap(
        spacing: 24,
        children: <Widget>[
          for (final item in items)
            SizedBox(
              width: 96,
              height: 96,
              child: LevixelSource(
                key: ValueKey<String>(item.id),
                controller: controller,
                itemId: item.id,
                cornerRadius: 12,
                child: Image.file(
                  File.fromUri(Uri.parse(item.url)),
                  fit: BoxFit.cover,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
