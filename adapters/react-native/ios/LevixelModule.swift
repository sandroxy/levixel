import ExpoModulesCore

public final class LevixelModule: Module {
    public func definition() -> ModuleDefinition {
        Name("Levixel")

        View(LevixelView.self) {
            Events("onSourcePress", "onViewerEvent")
            AsyncFunction("open") { (view: LevixelView, options: [String: Any], promise: Promise) in
                view.open(options: options, promise: promise)
            }
            AsyncFunction("close") { (view: LevixelView, promise: Promise) in view.close(promise: promise) }
            AsyncFunction("retry") { (view: LevixelView) in view.retry() }

            Prop("items") { (view: LevixelView, items: [[String: Any]]?) in
                view.items = items ?? []
            }
            Prop("index") { (view: LevixelView, index: Int?) in
                view.initialIndex = index ?? 0
            }
            Prop("galleryId") { (view: LevixelView, galleryId: String?) in
                view.galleryId = galleryId ?? ""
            }
            Prop("sourceCornerRadius") { (view: LevixelView, sourceCornerRadius: Double?) in
                view.sourceCornerRadius = CGFloat(sourceCornerRadius ?? 0)
            }
            OnViewDidUpdateProps { view in
                view.configureSourceView()
            }
        }
    }
}
