import Levixel
import UIKit

@MainActor
func verifyLevixelAdapterAPI() {
    let items: [LevixelMediaItem] = [.image(nil)]
    _ = LevixelArrayDataSource(items: items, itemIdentifiers: ["probe"])

    let sourceView = UIImageView()
    sourceView.registerLevixelSource(galleryId: "probe", itemIdentifier: "probe")
    sourceView.registerLevixelSource(galleryId: "probe", itemIdentifier: "probe", cornerRadius: 12)
    var configuration = LevixelViewerConfiguration(actions: [LevixelAction(id: "inspect", label: "Inspect")])
    configuration.actionLayout = .list
    configuration.actionListIcons = true
    configuration.onEvent = { event in _ = event.dictionary }
    let session = sourceView.presentLevixelViewer(dataSource: LevixelArrayDataSource(items: items), configuration: configuration)
    _ = session?.retry()
    _ = session?.sessionId
    session?.close(animated: false, completion: {})
    sourceView.unregisterLevixelSource()
}
