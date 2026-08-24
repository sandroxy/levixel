# Levixel for iOS

Binary Swift Package for the Levixel shared-transition image and video viewer.

Add the published package repository in Xcode, select a compatible `1.x`
version, link the `Levixel` product, and import the module:

```swift
import Levixel
```

The package manifest references the release XCFramework by HTTPS URL and pins
its checksum. The binary archive is built once, verified in the canonical
release pipeline, and then attached unchanged to the matching public tag.
