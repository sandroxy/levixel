package com.sandrox.levixel.reactnative

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.functions.Coroutine

class LevixelModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("Levixel")

        View(LevixelView::class) {
            Events("onSourcePress", "onViewerEvent", "onControllerReady")
            // Coroutine view functions run on the UI thread in both RN architectures.
            // Promise-style view functions can wait for an unrelated UI batch in Paper.
            AsyncFunction("open") Coroutine { view: LevixelView, options: Map<String, Any?> -> view.open(options) }
            AsyncFunction("close") Coroutine { view: LevixelView -> view.close() }
            AsyncFunction("retry") Coroutine { view: LevixelView -> view.retry() }

            Prop("isController") { view: LevixelView, isController: Boolean ->
                view.isController = isController
            }
            Prop("items") { view: LevixelView, items: Array<Map<String, Any?>> ->
                view.items = items.toList()
            }
            Prop("index") { view: LevixelView, index: Int ->
                view.initialIndex = index
            }
            Prop("galleryId") { view: LevixelView, galleryId: String ->
                view.galleryId = galleryId
            }
            Prop("sourceId") { view: LevixelView, sourceId: String ->
                view.sourceId = sourceId
            }
            Prop("sourceCornerRadius") { view: LevixelView, sourceCornerRadius: Double ->
                view.sourceCornerRadius = sourceCornerRadius.toFloat()
            }
            OnViewDidUpdateProps { view: LevixelView ->
                view.commitSourceBinding()
            }
        }
    }
}
