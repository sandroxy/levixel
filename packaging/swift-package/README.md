# Levixel for iOS

Binary Swift Package for the Levixel shared-transition image and video viewer.

Visible source media expands from its on-screen position, size, and corner
radius into the full-screen viewer, then returns to the corresponding source
when dismissed.

Levixel supports iOS 13.0 and newer.

In Xcode, choose **File > Add Package Dependencies** and enter:

```text
https://github.com/sandroxy/levixel.git
```

Use **Up to Next Major Version** with the latest stable
[GitHub Release](https://github.com/sandroxy/levixel/releases) as the lower
bound, or **Exact Version** when the application must pin one release exactly.
Link the `Levixel` product to the app target and import the module:

```swift
import Levixel
```

The package manifest references the release XCFramework by HTTPS URL and pins
its checksum, which Swift Package Manager verifies before using the binary.

See the [iOS integration guide](https://github.com/sandroxy/levixel#ios) for a
complete image and video setup example.
