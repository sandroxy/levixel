import type { LevixelAction, LevixelActionLayout } from './types.js';

/** Lives in the viewer's shadow root, above its media and transition layers. */
export class ActionSheet {
  readonly element = document.createElement('div');
  private readonly sheet = document.createElement('section');
  private readonly backdrop = document.createElement('button');
  private readonly content = document.createElement('div');
  private readonly reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  private previousFocus: HTMLElement | null = null;
  private animations: Animation[] = [];
  private closePromise: Promise<void> | undefined;
  private disposed = false;

  constructor(
    actions: readonly LevixelAction[],
    select: (action: LevixelAction) => void,
    cancel: () => void,
    layout: LevixelActionLayout = 'list',
    listIcons = false,
  ) {
    this.element.className = 'action-overlay';
    this.element.dataset.levixelControl = '';
    const chinese = navigator.language.startsWith('zh');
    const dismiss = this.backdrop;
    dismiss.type = 'button';
    dismiss.className = 'action-backdrop';
    dismiss.tabIndex = -1;
    dismiss.setAttribute('aria-label', chinese ? '关闭操作' : 'Close actions');
    dismiss.addEventListener('click', cancel);
    const sheet = this.sheet;
    sheet.className = 'action-sheet';
    sheet.dataset.layout = layout;
    sheet.dataset.icons = String(layout === 'grid' || listIcons);
    sheet.setAttribute('role', 'dialog');
    sheet.setAttribute('aria-modal', 'true');
    sheet.setAttribute('aria-label', chinese ? '媒体操作' : 'Media actions');
    const content = this.content;
    content.className = 'action-content';
    sheet.append(content);
    const groups = new Map<string, LevixelAction[]>();
    for (const action of actions) {
      const key = action.group ?? '';
      const group = groups.get(key) ?? [];
      group.push(action);
      groups.set(key, group);
    }
    for (const [name, actions] of groups) {
      const row = document.createElement('div');
      row.className = 'action-row';
      row.setAttribute('role', 'group');
      if (name) row.setAttribute('aria-label', name);
      for (const action of actions) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'action-button';
        button.dataset.actionId = action.id;
        button.dataset.destructive = String(action.destructive === true);
        button.disabled = action.disabled === true;
        if (layout === 'grid' || listIcons) {
          const tile = document.createElement('span');
          tile.className = 'action-icon';
          tile.setAttribute('aria-hidden', 'true');
          // Missing list icons reserve the same column without inventing an icon.
          if (action.icon) {
            const placeholder = document.createElement('span');
            placeholder.className = 'action-icon-placeholder';
            placeholder.textContent = '•••';
            tile.append(placeholder);
            const image = document.createElement('img');
            image.alt = '';
            image.draggable = false;
            image.addEventListener('load', () => { placeholder.hidden = true; });
            image.addEventListener('error', () => { image.remove(); });
            image.src = action.icon;
            tile.append(image);
          }
          button.append(tile);
        }
        const label = document.createElement('span');
        label.className = 'action-label';
        label.textContent = action.label;
        button.append(label);
        button.addEventListener('click', () => {
          if (!this.closePromise && !this.disposed && !action.disabled) select(action);
        });
        row.append(button);
      }
      content.append(row);
    }
    const cancelButton = document.createElement('button');
    cancelButton.type = 'button';
    cancelButton.className = 'action-cancel';
    cancelButton.textContent = chinese ? '取消' : 'Cancel';
    cancelButton.addEventListener('click', cancel);
    sheet.append(cancelButton);
    this.element.append(dismiss, sheet);
  }

  present(shadow: ShadowRoot): void {
    this.previousFocus = shadow.activeElement instanceof HTMLElement ? shadow.activeElement : null;
    if (!this.reducedMotion) {
      this.animate('translateY(100%)', 'translateY(0)', '0', '1', 280, 'cubic-bezier(0.22, 1, 0.36, 1)');
    }
    // The entering sheet starts below the viewport; scrolling to its focus target moves the media too.
    this.element.querySelector<HTMLButtonElement>('.action-sheet button:not(:disabled)')?.focus({ preventScroll: true });
  }

  focusButton(button: HTMLElement): void {
    button.focus({ preventScroll: true });
    if (!this.content.contains(button)) return;
    // Scroll only the drawer's own containers; scrolling ancestors can move
    // the media underneath, especially while the sheet is still entering.
    const row = button.closest<HTMLElement>('.action-row');
    for (const container of [row, this.content]) {
      if (!container) continue;
      const target = button.getBoundingClientRect();
      const viewport = container.getBoundingClientRect();
      if (target.left < viewport.left) container.scrollLeft += target.left - viewport.left;
      else if (target.right > viewport.right) container.scrollLeft += target.right - viewport.right;
      if (target.top < viewport.top) container.scrollTop += target.top - viewport.top;
      else if (target.bottom > viewport.bottom) container.scrollTop += target.bottom - viewport.bottom;
    }
  }

  close(animated = true): Promise<void> {
    if (this.closePromise) return this.closePromise;
    if (this.disposed) return Promise.resolve();
    if (animated && !this.reducedMotion) {
      // Preserve the visible position when closing before the entry finishes.
      const transform = getComputedStyle(this.sheet).transform;
      const opacity = getComputedStyle(this.backdrop).opacity;
      this.cancelAnimations();
      this.animate(transform, 'translateY(100%)', opacity, '0', 220, 'cubic-bezier(0.4, 0, 1, 1)');
    } else {
      this.cancelAnimations();
    }
    // Cancellation is expected when the entire viewer is replaced or destroyed.
    this.closePromise = Promise.allSettled(this.animations.map(animation => animation.finished)).then(() => this.destroy());
    return this.closePromise;
  }

  destroy(): void {
    this.disposed = true;
    this.cancelAnimations();
    this.element.remove();
  }

  restoreFocus(): void {
    if (this.previousFocus?.isConnected) this.previousFocus.focus({ preventScroll: true });
    this.previousFocus = null;
  }

  private animate(from: string, to: string, opacityFrom: string, opacityTo: string, duration: number, easing: string): void {
    const timing = { duration, easing, fill: 'both' as const };
    this.animations = [
      this.sheet.animate([{ transform: from }, { transform: to }], timing),
      this.backdrop.animate([{ opacity: opacityFrom }, { opacity: opacityTo }], timing),
    ];
    this.animations.forEach(animation => { void animation.finished.catch(() => {}); });
  }

  private cancelAnimations(): void {
    this.animations.forEach(animation => animation.cancel());
    this.animations = [];
  }
}
