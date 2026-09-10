import {
  cloneRect,
  cloneLevixelViewerEvent,
  LevixelSourceImageFit
} from '../model/LevixelModels';
import type { LevixelViewerEvent, RectMetrics } from '../model/LevixelModels';
import { intersectRects, isUsableRect } from '../model/LevixelTransitionGeometry';

interface LevixelSourceEntry {
  itemId: string;
  registrationId: number;
  snapshotId: string;
  viewportId: string;
  frameInWindow: RectMetrics | null;
  visible: boolean;
  cornerRadius: number;
  imageFit: LevixelSourceImageFit;
  setHidden: (hidden: boolean) => void;
}

interface LevixelViewportEntry {
  registrationId: number;
  frameInWindow: RectMetrics | null;
}

export interface LevixelResolvedSource {
  snapshotId: string;
  frameInWindow: RectMetrics;
  viewportInWindow: RectMetrics | null;
  cornerRadius: number;
  imageFit: LevixelSourceImageFit;
}

export interface LevixelSourceRegistration {
  registrationId: number;
  snapshotId: string;
}

export class LevixelViewerContext {
  private static nextContextId: number = 0;

  private readonly contextId: number;
  private nextRegistrationId: number = 0;
  private viewerRegistrationId: number = 0;
  private sessionSequence: number = 0;
  private closeHandler: (() => void) | null = null;
  private retryHandler: (() => boolean) | null = null;
  private backHandler: (() => boolean) | null = null;
  private listeners: Set<(event: LevixelViewerEvent) => void> = new Set<(event: LevixelViewerEvent) => void>();
  private openHandler: ((itemId: string) => void) | null = null;
  private prepareHandler: ((itemId: string) => void) | null = null;
  private readonly sources: Map<number, LevixelSourceEntry> = new Map<number, LevixelSourceEntry>();
  private readonly viewports: Map<string, LevixelViewportEntry> = new Map<string, LevixelViewportEntry>();
  private hiddenSourceId: string = '';

  constructor() {
    LevixelViewerContext.nextContextId += 1;
    this.contextId = LevixelViewerContext.nextContextId;
  }

  public close(): void { if (this.closeHandler !== null) this.closeHandler(); }
  public retry(): boolean { return this.retryHandler !== null ? this.retryHandler() : false; }
  public handleBack(): boolean { return this.backHandler !== null ? this.backHandler() : false; }

  public createSessionId(): string {
    this.sessionSequence += 1;
    return `levixel-harmony-${Date.now()}-${this.contextId}-${this.sessionSequence}`;
  }

  public onEvent(listener: (event: LevixelViewerEvent) => void): () => void {
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }

  public emit(event: LevixelViewerEvent): void {
    Array.from(this.listeners).forEach((listener: (event: LevixelViewerEvent) => void) => {
      listener(cloneLevixelViewerEvent(event));
    });
  }

  public open(itemId: string): void {
    this.requireIdentifier(itemId, 'itemId');
    if (this.openHandler === null) {
      throw new Error('LevixelController.open requires a mounted LevixelViewer using the same controller.');
    }
    this.openHandler(itemId);
  }

  public prepare(itemId: string): void {
    this.requireIdentifier(itemId, 'itemId');
    if (this.prepareHandler !== null) {
      this.prepareHandler(itemId);
    }
  }

  public registerViewer(
    openHandler: (itemId: string) => void,
    prepareHandler: (itemId: string) => void,
    closeHandler: (() => void) | null = null,
    retryHandler: (() => boolean) | null = null,
    backHandler: (() => boolean) | null = null
  ): number {
    if (this.openHandler !== null) {
      throw new Error('A LevixelController cannot be attached to more than one mounted LevixelViewer.');
    }
    this.viewerRegistrationId = this.allocateRegistrationId();
    this.openHandler = openHandler;
    this.prepareHandler = prepareHandler;
    this.closeHandler = closeHandler;
    this.retryHandler = retryHandler;
    this.backHandler = backHandler;
    return this.viewerRegistrationId;
  }

  public unregisterViewer(registrationId: number): void {
    if (registrationId !== this.viewerRegistrationId) {
      return;
    }
    this.openHandler = null;
    this.prepareHandler = null;
    this.closeHandler = null;
    this.retryHandler = null;
    this.backHandler = null;
    this.viewerRegistrationId = 0;
    this.setHiddenSource('');
  }

  public registerSource(
    itemId: string,
    viewportId: string,
    cornerRadius: number,
    imageFit: LevixelSourceImageFit,
    setHidden: (hidden: boolean) => void
  ): LevixelSourceRegistration {
    this.requireIdentifier(itemId, 'itemId');
    this.requireOptionalIdentifier(viewportId, 'viewportId');
    this.requireCornerRadius(cornerRadius);
    this.requireImageFit(imageFit);
    const registrationId: number = this.allocateRegistrationId();
    const snapshotId: string = `levixel-source-${this.contextId}-${registrationId}`;
    this.sources.set(registrationId, {
      itemId: itemId,
      registrationId: registrationId,
      snapshotId: snapshotId,
      viewportId: viewportId,
      frameInWindow: null,
      visible: false,
      cornerRadius: cornerRadius,
      imageFit: imageFit,
      setHidden: setHidden
    });
    setHidden(this.hiddenSourceId === itemId);
    return {
      registrationId: registrationId,
      snapshotId: snapshotId
    };
  }

  public updateSourceFrame(itemId: string, registrationId: number, frameInWindow: RectMetrics): void {
    const source: LevixelSourceEntry | null = this.registeredSource(itemId, registrationId);
    if (source === null) {
      return;
    }
    source.frameInWindow = cloneRect(frameInWindow);
  }

  public updateSourceConfiguration(
    itemId: string,
    registrationId: number,
    viewportId: string,
    cornerRadius: number,
    imageFit: LevixelSourceImageFit
  ): void {
    this.requireOptionalIdentifier(viewportId, 'viewportId');
    this.requireCornerRadius(cornerRadius);
    this.requireImageFit(imageFit);
    const source: LevixelSourceEntry | null = this.registeredSource(itemId, registrationId);
    if (source !== null) {
      source.viewportId = viewportId;
      source.cornerRadius = cornerRadius;
      source.imageFit = imageFit;
    }
  }

  public viewerSnapshotId(itemId: string): string {
    return `levixel-viewer-${this.contextId}-${itemId}`;
  }

  public updateSourceVisibility(itemId: string, registrationId: number, visible: boolean): void {
    const source: LevixelSourceEntry | null = this.registeredSource(itemId, registrationId);
    if (source !== null) {
      source.visible = visible;
    }
  }

  public unregisterSource(itemId: string, registrationId: number): void {
    const source: LevixelSourceEntry | undefined = this.sources.get(registrationId);
    if (source === undefined || source.itemId !== itemId) {
      return;
    }
    source.setHidden(false);
    this.sources.delete(registrationId);
  }

  public resolveSource(itemId: string): LevixelResolvedSource | null {
    const matches: LevixelSourceEntry[] = [];
    this.sources.forEach((candidate: LevixelSourceEntry) => {
      if (candidate.itemId === itemId && this.isResolvableSource(candidate)) {
        matches.push(candidate);
      }
    });
    if (matches.length === 0) {
      return null;
    }
    if (matches.length > 1) {
      throw new Error(`LevixelSource itemId "${itemId}" has more than one visible mounted source.`);
    }
    const source: LevixelSourceEntry = matches[0];
    if (source.frameInWindow === null) {
      return null;
    }

    let viewportInWindow: RectMetrics | null = null;
    if (source.viewportId.length > 0) {
      const viewport: LevixelViewportEntry | undefined = this.viewports.get(source.viewportId);
      if (viewport === undefined || viewport.frameInWindow === null) {
        return null;
      }
      viewportInWindow = cloneRect(viewport.frameInWindow);
    }

    return {
      snapshotId: source.snapshotId,
      frameInWindow: cloneRect(source.frameInWindow),
      viewportInWindow: viewportInWindow,
      cornerRadius: source.cornerRadius,
      imageFit: source.imageFit
    };
  }

  public setHiddenSource(itemId: string): void {
    if (this.hiddenSourceId === itemId) {
      return;
    }
    this.hiddenSourceId = itemId;
    this.sources.forEach((source: LevixelSourceEntry) => {
      source.setHidden(source.itemId === itemId);
    });
  }

  public registerViewport(viewportId: string): number {
    this.requireIdentifier(viewportId, 'viewportId');
    if (this.viewports.has(viewportId)) {
      throw new Error(`LevixelSourceViewport viewportId "${viewportId}" is mounted more than once in one LevixelViewer.`);
    }
    const registrationId: number = this.allocateRegistrationId();
    this.viewports.set(viewportId, {
      registrationId: registrationId,
      frameInWindow: null
    });
    return registrationId;
  }

  public updateViewportFrame(viewportId: string, registrationId: number, frameInWindow: RectMetrics): void {
    const viewport: LevixelViewportEntry | undefined = this.viewports.get(viewportId);
    if (viewport === undefined || viewport.registrationId !== registrationId) {
      return;
    }
    viewport.frameInWindow = cloneRect(frameInWindow);
  }

  public unregisterViewport(viewportId: string, registrationId: number): void {
    const viewport: LevixelViewportEntry | undefined = this.viewports.get(viewportId);
    if (viewport !== undefined && viewport.registrationId === registrationId) {
      this.viewports.delete(viewportId);
    }
  }

  private registeredSource(itemId: string, registrationId: number): LevixelSourceEntry | null {
    const source: LevixelSourceEntry | undefined = this.sources.get(registrationId);
    return source !== undefined && source.itemId === itemId ? source : null;
  }

  private isResolvableSource(source: LevixelSourceEntry): boolean {
    if (!source.visible || source.frameInWindow === null || !isUsableRect(source.frameInWindow)) {
      return false;
    }
    if (source.viewportId.length === 0) {
      return true;
    }
    const viewport: LevixelViewportEntry | undefined = this.viewports.get(source.viewportId);
    return viewport !== undefined && viewport.frameInWindow !== null &&
      intersectRects(source.frameInWindow, viewport.frameInWindow) !== null;
  }

  private allocateRegistrationId(): number {
    this.nextRegistrationId += 1;
    return this.nextRegistrationId;
  }

  private requireIdentifier(value: string, name: string): void {
    if (value.trim().length === 0) {
      throw new Error(`Levixel ${name} must be a non-empty string.`);
    }
  }

  private requireOptionalIdentifier(value: string, name: string): void {
    if (value.length > 0 && value.trim().length === 0) {
      throw new Error(`Levixel ${name} must be empty or a non-empty string.`);
    }
  }

  private requireCornerRadius(value: number): void {
    if (!Number.isFinite(value) || value < 0) {
      throw new Error('Levixel source cornerRadius must be a finite non-negative number.');
    }
  }

  private requireImageFit(value: LevixelSourceImageFit): void {
    if (value !== LevixelSourceImageFit.COVER &&
      value !== LevixelSourceImageFit.CONTAIN &&
      value !== LevixelSourceImageFit.FILL) {
      throw new Error('Levixel source imageFit must be COVER, CONTAIN, or FILL.');
    }
  }
}
