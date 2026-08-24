# Levixel For UniApp

The UniApp adapter packages thin Android and iOS bridges around the canonical
Levixel native artifacts. It does not copy either native viewer core.

## Public SDK

Install the generated `Sandrox-Levixel` directory under the consumer
project's `nativeplugins/` directory, enable it in `manifest.json`, and import
its JavaScript SDK:

```js
import {
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
} from '@/nativeplugins/Sandrox-Levixel/js_sdk/index.js'
```

Each rendered source element must use the same selector and order as `items`.
For deterministic shared transitions, prepare each item first and render the
returned local `src` in the HTML image. That exact managed file is also handed
to the native viewer, so an image that is visible and clickable cannot still be
waiting on a second transition-only download. Keep bulk preparation bounded;
the example app uses three workers and passes `priority: true` to each worker.
Some UniApp runtimes reuse one temporary path across different `getImageInfo`
requests, so remote previews are downloaded into distinct managed files.
The adapter keeps DCloud's virtual path for lifecycle management and resolves
a native-readable `file://` URL before handing the preview across the bridge.
Saved previews use an LRU limit and files left by a terminated process are
removed on the next startup. Android CSS pixels are normalized to native
window pixels by an explicit `rectScale`; no hidden native image view is
created for an HTML source:

```js
const prepared = await prepareLevixelItem(item, { priority: true })
if (prepared)
  previewSources[item.id] = prepared.src

// Call this from the local image's load handler. It records that the source is
// actually decoded and preserves compatibility with the warmup-only workflow.
warmupLevixelItem(item, loadEvent)

await openLevixelFromSelector({
  items,
  index,
  sourceSelector: '.levixel-source',
  sourceStyles: items.map(() => ({ objectFit: 'cover', cornerRadius: 6 })),
})
```

`sourceVisibility` defaults to `visible`. This is the verified UniApp handoff
policy: the HTML source remains underneath the native transition to avoid a
WebView texture flash. Set it to `hidden` only when the page handles
`sourceVisibilityChange` events and that behavior has been verified in its
actual WebView host.

## Package And Verify

```sh
DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
  ./scripts/package-uniapp.sh
./scripts/verify-uniapp.sh
```

The verifier checks the final ZIP bytes. Host-level acceptance must install
that exact ZIP in an artifact-only UniApp consumer, then build a matching
custom base or offline package without rebuilding either native core.
