# Flutter adapter

`sandrox_levixel` connects Flutter thumbnails to the Levixel Android and iOS
viewers. Flutter renders the host interface; the existing native cores own media
loading, paging, zoom, drag dismissal, video playback, actions, and transitions.

## Installation

Native builds require a prepared `levixel-flutter-<version>.zip` package. Verify
its SHA-256 against the accompanying `.sha256` file, then extract its
`sandrox_levixel/` directory under your application's `vendor/` directory.
Add the extracted package as a path dependency:

```yaml
dependencies:
  flutter:
    sdk: flutter
  sandrox_levixel:
    path: vendor/sandrox_levixel
```

Run `flutter pub get` and rebuild the application. Keep the extracted package
intact: it includes the matching Android Maven repository, the device and
simulator iOS XCFramework, native provenance, and legal notices. Android resolves
the core from that embedded Maven repository; its runtime dependencies still
require access to Google Maven, Maven Central, and JitPack.

Android requires API 24 or later, compile SDK 36, and Java 17. iOS requires iOS 15
or later. The adapter declares Flutter 3.44 or later and supports Flutter's Swift
Package Manager and CocoaPods integration. Set the application's minimum
deployment targets accordingly.

The repository's `adapters/flutter` directory contains adapter source without
native binaries; a Git dependency on that directory alone is not installable.
`publish_to: none` prevents accidental pub.dev publication. Maintainers building
the package should use the repository's
[development guide](https://github.com/sandroxy/levixel/blob/master/DEVELOPMENT.md).

## Gallery and source widgets

Create and retain a controller in the host widget's state, then dispose it with
that state. Media IDs must be unique within a gallery and remain stable across
host reordering. Locations are native-readable URLs or absolute file paths;
Flutter asset keys and `ImageProvider` instances are not native media locations.

```dart
import 'package:flutter/widgets.dart';
import 'package:sandrox_levixel/levixel.dart';

final controller = LevixelController(
  galleryId: 'photos',
  items: [
    LevixelMedia(
      id: 'lake',
      type: LevixelMediaType.image,
      url: 'https://example.com/lake.jpg',
    ),
  ],
);

// Place this in the host widget's build method.
LevixelSource(
  controller: controller,
  itemId: 'lake',
  cornerRadius: 12,
  child: Image.network(
    'https://example.com/lake.jpg',
    width: 120,
    height: 120,
    fit: BoxFit.cover,
  ),
);
```

Tapping a source opens its item. Programmatic opening accepts `itemId` or `index`:

```dart
await controller.open(itemId: 'lake');
await controller.close();
controller.dispose();
```

`open()` completes when presentation has been requested. Observe `opened` for
the native transition completion. `close()` completes after native dismissal
and Flutter thumbnail restoration. Opening another controller closes the active
viewer in the same Flutter engine. Closing an inactive controller does not close
another gallery. Disposal closes an owned viewer asynchronously and ends its
event stream; await `close()` first when dismissal completion matters.
An opening request replaced, closed, or suspended before presentation fails with
`PlatformException` code `OPEN_CANCELLED`. Source taps handle this expected
cancellation without reporting an application error. When Flutter has stopped
scheduling frames, `close()` dismisses without animation and releases the
session without waiting for a foreground frame.

Assign `controller.items` when the host gallery changes. An open viewer retains
its opening media and action snapshots, so events always identify that session's
items and indices. Return transitions resolve mounted thumbnails by stable
item identity, including after host reordering. Removing a source permits the
native viewer's fallback dismissal. Multiple source widgets may reference the
same item; the clicked widget supplies the preferred transition source.

## Transitions

A source exports the decoded image, visible rectangle, centered fit, and uniform
corner radius to the native core. It does not create a platform view for each
thumbnail. A temporary native preview covers the handoff while the corresponding
Flutter image is hidden or restored.

Shared transitions require one decoded, opaque image using centered `cover`,
`contain`, or `fill` sizing, without rotation, skew, nonuniform scaling, tint,
repetition, nine-patch stretching, or directional mirroring. Arbitrary paint
effects and custom clip shapes cannot be reconstructed from an image and
rectangle; use a plain image
inside `LevixelSource` for matching transitions. Unavailable or unsupported
sources use the native fade transition. The exported preview is bounded to
1,024 pixels per dimension; the viewer independently loads the full media URL.

## Actions and events

Both `LevixelSource` and `controller.open()` accept `theme`, `actions`,
`actionLayout`, and `actionListIcons`. Actions have stable IDs, labels, optional
native-readable icon locations and groups, disabled/destructive flags, and an
`onSelected` callback. Grid actions require an icon. Callbacks belong to the
opening snapshot and receive the native event's media identity.

`controller.events` emits `indexChange`, `opened`, `longPress`, `mediaLoad`,
`mediaError`, `action`, and `dismiss`. Each event exposes its timestamp, session ID, gallery ID,
item ID, index, and native payload. Subscribe before opening to receive initial
events, and cancel host subscriptions when they are no longer needed. Long press
emits `longPress` even when the opening has no actions; an empty action list
leaves the viewer open without showing a drawer.
The initial `indexChange` precedes `opened`. Media loading and preloading can
emit events before opening finishes or for an adjacent item; use `itemId` to
identify their media. A thumbnail preview alone does not emit `mediaLoad`.
`controller.retry()` requests the native viewer's current retry operation and
reports whether it was accepted.
