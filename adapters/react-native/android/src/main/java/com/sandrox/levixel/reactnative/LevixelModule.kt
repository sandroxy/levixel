package com.sandrox.levixel.reactnative

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class LevixelModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("Levixel")

        View(LevixelView::class) {
            Events("onIndexChange")

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
            Prop("theme") { view: LevixelView, theme: LevixelTheme ->
                view.theme = theme
            }
        }
    }
}
