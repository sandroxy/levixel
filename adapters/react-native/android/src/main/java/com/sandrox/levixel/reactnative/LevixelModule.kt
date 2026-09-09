package com.sandrox.levixel.reactnative

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.Promise

class LevixelModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("Levixel")

        View(LevixelView::class) {
            Events("onSourcePress", "onViewerEvent")
            AsyncFunction("open") { view: LevixelView, options: Map<String, Any?> -> view.open(options) }
            AsyncFunction("close") { view: LevixelView, promise: Promise -> view.close(promise) }
            AsyncFunction("retry") { view: LevixelView -> view.retry() }

            Prop("items") { view: LevixelView, items: Array<Map<String, Any?>> ->
                view.items = items.toList()
            }
            Prop("index") { view: LevixelView, index: Int ->
                view.initialIndex = index
            }
            Prop("galleryId") { view: LevixelView, galleryId: String ->
                view.galleryId = galleryId
            }
            Prop("sourceCornerRadius") { view: LevixelView, sourceCornerRadius: Double ->
                view.sourceCornerRadius = sourceCornerRadius.toFloat()
            }
        }
    }
}
