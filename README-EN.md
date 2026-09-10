# Levixel

[中文](README.md)

Levixel is a native-feeling image and video viewer built around shared transitions, horizontal paging, pinch-to-zoom, zoomed panning, drag-to-dismiss, and video playback.

A shared transition starts from the visible source media's on-screen position, size, and corner radius, expands that content continuously into the full-screen viewer, and returns it to the corresponding source when dismissed. Even when the implementation hands off between a thumbnail, loading state, and original media, the user continues to perceive and manipulate one coherent piece of content.

<p align="center">
  <img src="docs/assets/levixel-demo.gif" width="400" alt="Levixel shared transition, paging, and return animation">
</p>

The interaction direction draws inspiration from the media-centered direct manipulation found in Google Photos and Apple's Photos app on iPhone. Those products are interaction references only; Levixel is not affiliated with, endorsed by, or based on their code. Levixel's own open-source lineage is documented under [License and provenance](#license-and-provenance).

## Capabilities

- Mixed image and video paging
- Source-anchored shared transitions for both opening and return
- Pinch zoom, zoomed panning, and double-tap reset
- Drag dismissal while the image is not zoomed, plus tap dismissal and system back handling
- Continuous handoff across thumbnails, loading states, original images, and video frames
- Image and video long-press events with configurable list or grid action sheets
- Session and loading events with media identity, visible failure controls, and programmatic retry
- Published packages for Android, iOS, HarmonyOS, React Native, UniApp, and supported modern Web browsers

## Platforms and distribution

| Platform | Recommended channel | Integration |
| --- | --- | --- |
| Android | [Maven Central](https://central.sonatype.com/artifact/io.gitee.sandrox/levixel) · `io.gitee.sandrox:levixel` | [Android guide](native/android/README.md), with an offline AAR mirror |
| iOS | [Swift Package](https://github.com/sandroxy/levixel) | [iOS guide](native/ios/README.md), with checksum-verified XCFramework |
| HarmonyOS | [OHPM](https://ohpm.openharmony.cn/#/cn/detail/@sandrox%2Flevixel) · `@sandrox/levixel` | Native HAR with an offline mirror on GitHub Releases |
| React Native / Expo | [npm](https://www.npmjs.com/package/@sandrox/levixel) · `@sandrox/levixel` | React Native components with the required Android/iOS native runtimes included |
| UniApp | [DCloud Marketplace](https://ext.dcloud.net.cn/plugin?id=29394) | Classic uni-app and uni-app x Vapor Android/iOS Apps |
| Web | [npm](https://www.npmjs.com/package/@sandrox/levixel-web) · `@sandrox/levixel-web` | Framework-independent ESM browser runtime |

See [GitHub Releases](https://github.com/sandroxy/levixel/releases) and [CHANGELOG.md](CHANGELOG.md) for version history, checksums, and offline artifacts. Each package registry is the source of truth for the versions currently available through that channel; consult each platform guide for its exact capabilities and host requirements.

## Android

The minimum supported Android version is API 21.

Install through Maven Central using the latest stable version shown by that channel:

```kotlin
dependencies {
    implementation("io.gitee.sandrox:levixel:<version>")
}
```

See the [Android guide](native/android/README.md) for repository setup, opening a viewer, dynamic source binding, long-press actions, and events.

## iOS

The minimum supported iOS version is 13.0.

In Xcode, choose **File > Add Package Dependencies** and enter:

```text
https://github.com/sandroxy/levixel.git
```

Use **Up to Next Major Version** with the latest stable release shown on [GitHub Releases](https://github.com/sandroxy/levixel/releases) as the lower bound; Xcode will resolve compatible updates within that major version. Use **Exact Version** when the application must pin one release exactly. Then link the `Levixel` product to the app target.

See the [iOS guide](native/ios/README.md) for media data, source binding, long-press actions, and session control. Swift Package Manager verifies the download against the checksum recorded in the package manifest.

## HarmonyOS

The minimum supported HarmonyOS version is API 23. The current HAR targets phone devices.

Install the currently published package from OHPM:

```sh
ohpm install @sandrox/levixel
```

The matching GitHub Release also provides the HAR and its SHA-256 file for offline or manual integration.

See the [HarmonyOS guide](native/harmonyos/levixel/README.md) for the component API and a complete example.

## React Native / Expo

```sh
pnpm add @sandrox/levixel
npx expo prebuild
```

The package includes the React Native integration and the required Android/iOS native runtimes, so the native core does not need to be integrated separately. Dynamic, paginated, and virtualized lists bind mounted cells by stable media identity with `Levixel.Source itemId`. Rounded sources put a numeric `borderRadius` and `overflow: 'hidden'` on `Levixel.Source` itself, so one style controls both visible clipping and native transition geometry. See the [React Native adapter guide](adapters/react-native/README.md) for the component API and host requirements.

## UniApp

For new projects, install the plugin from the [DCloud Marketplace](https://ext.dcloud.net.cn/plugin?id=29394). The UTS plugin supports classic uni-app Vue 2 / Vue 3 App pages and uni-app x Vapor Android/iOS Apps; x VDOM is not supported. Both paths share one public JavaScript API and the same platform runtimes. Dynamic lists bind mounted sources with `initialItemId + sourceBindings`; return transitions use the source rectangle's real intersection with the effective page viewport, sharing the transition while any positive area remains visible and fading safely when none does. `sourceVisibility` remains `visible` by default to prevent a last-frame source flash during WebView/Vapor close handoff.

See the [UniApp guide](uni_modules/Sandrox-Levixel/readme.md) for the complete compatibility boundary, loading-state integration, and examples. Matching GitHub Releases also provide the UTS ZIP and checksum for direct downloads and offline archives.

Classic uni-app Android/iOS projects that choose the App native-plugin workflow can use the separately published `levixel-uniapp-legacy-<version>.zip`. It uses the same-version public SDK, platform runtimes, and native cores, but it is not the DCloud UTS Marketplace package and does not support uni-app x.

## Web

```sh
pnpm add @sandrox/levixel-web
```

The Web package uses the browser DOM, Pointer Events, the Web Animations API, and native media elements for shared transitions, paging, zoom, pan, drag dismissal, and video controls, including sparse stable-id bindings for virtualized sources. It defaults to `sourceVisibility: hidden` without changing UniApp's platform-specific `visible` default.

The verified browser matrix covers macOS Chrome, macOS Safari, Android Chrome, and iOS Safari. See the [Web guide](adapters/web/README.md) for the API, browser boundary, and accessibility behavior.

## Source and releases

See [DEVELOPMENT.md](DEVELOPMENT.md) for local builds, tests, and SDK prerequisites. See [RELEASING.md](RELEASING.md) for signing and channel-publication procedures.

## License and provenance

Levixel is released under the MIT License and contains traceable MIT-licensed derivative work. Source lineage, license terms, and retained notices are documented in [PROVENANCE.md](PROVENANCE.md), [LICENSE](LICENSE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
