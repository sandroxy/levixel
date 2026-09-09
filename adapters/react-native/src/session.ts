import type { LevixelAction, LevixelEvent } from './types';

/** Callback ownership follows the open request, including events before open resolves. */
export class LevixelSessions {
  private actions = new Map<string, readonly LevixelAction[]>();

  begin(requestId: string, actions: readonly LevixelAction[]): void {
    this.actions.set(requestId, actions.map(action => ({ ...action })));
  }

  end(requestId: string): void { this.actions.delete(requestId); }

  dispatch(requestId: string, event: LevixelEvent, listener?: (event: LevixelEvent) => void): void {
    const actions = this.actions.get(requestId);
    if (actions === undefined) return;
    const callback = event.type === 'action'
      ? actions.find(action => action.id === event.payload.actionId && !action.disabled)?.onPress
      : undefined;
    if (event.type === 'dismiss') this.end(requestId);
    // Keep callback context independent from a listener mutating its event argument.
    const context = event.type === 'action' ? { ...event.payload } : undefined;
    try { listener?.(event); }
    finally { if (context !== undefined) callback?.(context); }
  }
}
