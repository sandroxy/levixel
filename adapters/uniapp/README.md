# Levixel For UniApp

The UniApp adapter packages thin Android and iOS bridges around the canonical
Levixel native artifacts. It does not copy either native viewer core.

## Public SDK

Install the generated `SandroxUniPlugin-Levixel` directory under the consumer
project's `nativeplugins/` directory, enable it in `manifest.json`, and import
its JavaScript SDK:

```js
import {
  openLevixelFromSelector,
  warmupLevixelItem,
} from '@/nativeplugins/SandroxUniPlugin-Levixel/js_sdk/index.js'
```

Each rendered source element must use the same selector and order as `items`.
The helper measures those DOM rectangles and prepares identity-safe local
previews as each HTML image finishes loading. Some UniApp runtimes reuse one
temporary path across different `getImageInfo` requests, so remote previews are
downloaded into distinct managed files instead. Background preparation remains
serialized to avoid unnecessary network pressure, while the tapped item may
use its own isolated foreground download and cannot be blocked by that queue.
The adapter keeps DCloud's virtual path for lifecycle management and resolves
a native-readable `file://` URL before handing the preview across the bridge.
A source confirmed visible by its load event gets a bounded foreground wait;
an unavailable source falls back quickly to its stable remote URL. Saved
previews use an LRU limit and files left by a terminated process are removed on
the next startup. Android CSS pixels are normalized to native window pixels by
an explicit `rectScale`; no hidden native image view is created for an HTML
source:

```js
// The returned promise is optional; normal image load handlers can ignore it.
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

The verifier checks the final ZIP bytes and stages that same package in the
shared UniApp test host. Open `uniapp-plugins-test` in HBuilderX only after this
step, then build a matching custom base or offline package.
