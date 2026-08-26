const TAP_MOVEMENT_TOLERANCE = 10;
const COMPATIBILITY_CLICK_WINDOW = 800;

interface TouchCandidate {
  pointerId: number;
  startX: number;
  startY: number;
  moved: boolean;
}

export type LevixelSourceActivationListener = () => void;

/**
 * Installs source activation that remains responsive after a touch drag while
 * preserving native click activation for mouse, keyboard, and assistive input.
 */
export function onLevixelSourceActivate(
  element: HTMLElement,
  listener: LevixelSourceActivationListener,
): () => void {
  if (typeof window === 'undefined' || typeof HTMLElement === 'undefined')
    throw new Error('Levixel source activation requires a browser document');
  if (!(element instanceof HTMLElement))
    throw new Error('Levixel source activation requires an HTMLElement');
  if (typeof listener !== 'function')
    throw new Error('Levixel source activation listener must be a function');

  let candidate: TouchCandidate | undefined;
  let suppressCompatibilityClickUntil = Number.NEGATIVE_INFINITY;
  let suppressionTimer: number | undefined;

  const clearSuppression = (): void => {
    suppressCompatibilityClickUntil = Number.NEGATIVE_INFINITY;
    if (suppressionTimer !== undefined) {
      window.clearTimeout(suppressionTimer);
      suppressionTimer = undefined;
    }
  };

  const suppressCompatibilityClick = (): void => {
    clearSuppression();
    suppressCompatibilityClickUntil = performance.now() + COMPATIBILITY_CLICK_WINDOW;
    suppressionTimer = window.setTimeout(clearSuppression, COMPATIBILITY_CLICK_WINDOW);
  };

  const handlePointerDown = (event: PointerEvent): void => {
    if (event.pointerType === 'mouse')
      return;
    if (!event.isPrimary || event.button !== 0) {
      if (candidate)
        candidate.moved = true;
      return;
    }
    candidate = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      moved: false,
    };
  };

  const handlePointerMove = (event: PointerEvent): void => {
    if (!candidate || candidate.pointerId !== event.pointerId)
      return;
    if (movementFromStart(candidate, event) > TAP_MOVEMENT_TOLERANCE)
      candidate.moved = true;
  };

  const handlePointerEnd = (event: PointerEvent): void => {
    if (!candidate || candidate.pointerId !== event.pointerId)
      return;
    const completed = event.type === 'pointerup'
      && event.isPrimary
      && !candidate.moved
      && movementFromStart(candidate, event) <= TAP_MOVEMENT_TOLERANCE;
    candidate = undefined;
    if (event.type === 'pointerup')
      suppressCompatibilityClick();
    if (!completed)
      return;
    listener();
  };

  const handleClick = (event: MouseEvent): void => {
    const pointerType = typeof PointerEvent !== 'undefined' && event instanceof PointerEvent
      ? event.pointerType
      : undefined;
    const compatibilityTouchClick = event.detail !== 0
      && performance.now() <= suppressCompatibilityClickUntil
      && pointerType !== 'mouse';
    if (compatibilityTouchClick) {
      clearSuppression();
      return;
    }
    listener();
  };

  element.addEventListener('pointerdown', handlePointerDown);
  element.addEventListener('pointermove', handlePointerMove, { passive: true });
  element.addEventListener('pointerup', handlePointerEnd);
  element.addEventListener('pointercancel', handlePointerEnd);
  element.addEventListener('click', handleClick);

  return () => {
    candidate = undefined;
    clearSuppression();
    element.removeEventListener('pointerdown', handlePointerDown);
    element.removeEventListener('pointermove', handlePointerMove);
    element.removeEventListener('pointerup', handlePointerEnd);
    element.removeEventListener('pointercancel', handlePointerEnd);
    element.removeEventListener('click', handleClick);
  };
}

function movementFromStart(candidate: TouchCandidate, event: PointerEvent): number {
  return Math.hypot(event.clientX - candidate.startX, event.clientY - candidate.startY);
}
