import Levixel
import UIKit

@MainActor
func verifyLevixelAdapterAPI() {
    let items: [LevixelMediaItem] = [.image(nil)]
    _ = LevixelArrayDataSource(items: items, itemIdentifiers: ["probe"])

    let sourceView = UIImageView()
    sourceView.registerLevixelSource(galleryId: "probe", itemIdentifier: "probe")
    sourceView.unregisterLevixelSource()
}
