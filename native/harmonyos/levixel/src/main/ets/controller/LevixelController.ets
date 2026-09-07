import { LevixelViewerContext } from './LevixelViewerContext';

const contexts: WeakMap<LevixelController, LevixelViewerContext> =
  new WeakMap<LevixelController, LevixelViewerContext>();

export class LevixelController {
  constructor() {
    contexts.set(this, new LevixelViewerContext());
  }

  public open(itemId: string): void {
    resolveLevixelContext(this).open(itemId);
  }
}

export function resolveLevixelContext(controller: LevixelController | null): LevixelViewerContext {
  if (controller === null) {
    throw new Error('LevixelViewer, LevixelSource, and LevixelSourceViewport require the same LevixelController instance.');
  }
  const context: LevixelViewerContext | undefined = contexts.get(controller);
  if (context === undefined) {
    throw new Error('Levixel controller must be an instance created with new LevixelController().');
  }
  return context;
}
