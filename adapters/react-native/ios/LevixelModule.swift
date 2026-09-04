import ExpoModulesCore

public final class LevixelModule: Module {
    public func definition() -> ModuleDefinition {
        Name("Levixel")

        View(LevixelView.self) {
            Events("onIndexChange")

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
            Prop("theme") { (view: LevixelView, theme: LevixelTheme?) in
                view.theme = theme ?? .dark
            }

            OnViewDidUpdateProps { view in
                view.configureSourceView()
            }
        }
    }
}
