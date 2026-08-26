export const LEVIXEL_STYLES = String.raw`
  :host {
    all: initial;
    position: fixed;
    z-index: 2147483647;
    display: block;
    overflow: hidden;
    contain: strict;
    color-scheme: dark;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    -webkit-tap-highlight-color: transparent;
  }

  :host([data-theme="light"]) {
    color-scheme: light;
  }

  *, *::before, *::after {
    box-sizing: border-box;
  }

  button, input {
    font: inherit;
  }

  .root {
    position: absolute;
    inset: 0;
    overflow: hidden;
    outline: none;
    touch-action: none;
    user-select: none;
    -webkit-user-select: none;
  }

  .backdrop,
  .content,
  .track,
  .page,
  .media-shell,
  .video-shell {
    position: absolute;
    inset: 0;
  }

  .backdrop {
    background: #000;
    opacity: 0;
    will-change: opacity;
  }

  :host([data-theme="light"]) .backdrop {
    background: #fff;
  }

  .content {
    opacity: 0;
    overflow: hidden;
    will-change: opacity;
  }

  .track {
    display: flex;
    right: auto;
    bottom: auto;
    height: 100%;
    will-change: transform;
  }

  .page {
    position: relative;
    inset: auto;
    flex: 0 0 auto;
    overflow: hidden;
    transform-origin: 50% 50%;
    will-change: transform;
  }

  .media-shell,
  .video-shell {
    overflow: hidden;
  }

  .image,
  .video,
  .poster {
    position: absolute;
    display: block;
    max-width: none;
    max-height: none;
    margin: 0;
    border: 0;
    background: transparent;
    transform-origin: 50% 50%;
    will-change: transform, opacity;
    -webkit-user-drag: none;
    user-select: none;
  }

  .video,
  .poster {
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
  }

  .video {
    opacity: 0;
  }

  .poster {
    opacity: 1;
  }

  .spinner {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 24px;
    height: 24px;
    margin: -12px 0 0 -12px;
    border: 2px solid rgb(255 255 255 / 25%);
    border-top-color: #fff;
    border-radius: 50%;
    opacity: 0;
    pointer-events: none;
    animation: levixel-spin 700ms linear infinite;
  }

  :host([data-theme="light"]) .spinner {
    border-color: rgb(0 0 0 / 20%);
    border-top-color: #000;
  }

  .spinner[data-visible="true"] {
    opacity: 1;
  }

  @keyframes levixel-spin {
    to { transform: rotate(360deg); }
  }

  .video-controls {
    position: absolute;
    left: max(12px, env(safe-area-inset-left));
    right: max(12px, env(safe-area-inset-right));
    bottom: max(20px, env(safe-area-inset-bottom));
    height: 56px;
    display: grid;
    grid-template-columns: 44px minmax(72px, 1fr) auto;
    align-items: center;
    gap: 10px;
    padding: 0 12px 0 10px;
    color: #fff;
    background: rgb(0 0 0 / 50%);
    border-radius: 12px;
    opacity: 0;
    pointer-events: none;
    transition: opacity 220ms ease-in-out;
  }

  .video-controls[data-visible="true"] {
    opacity: 1;
    pointer-events: auto;
  }

  .control-button,
  .close-button {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    padding: 0;
    color: #fff;
    background: transparent;
    border: 0;
    border-radius: 22px;
    cursor: pointer;
    touch-action: manipulation;
  }

  .control-button:focus-visible,
  .close-button:focus-visible,
  .timeline:focus-visible {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }

  .control-button svg,
  .close-button svg {
    width: 23px;
    height: 23px;
    fill: currentColor;
  }

  .timeline {
    width: 100%;
    min-width: 0;
    accent-color: #fff;
    cursor: pointer;
    touch-action: pan-x;
  }

  .time-label {
    min-width: 88px;
    color: #fff;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    text-align: right;
    white-space: nowrap;
  }

  .close-button {
    position: absolute;
    left: max(8px, env(safe-area-inset-left));
    top: max(8px, env(safe-area-inset-top));
    z-index: 3;
    color: #fff;
    opacity: 0;
    pointer-events: none;
    transition: opacity 180ms ease-in-out;
  }

  :host([data-theme="light"]) .close-button {
    color: #000;
  }

  .close-button[data-visible="true"] {
    opacity: 1;
    pointer-events: auto;
  }

  .snapshot {
    position: absolute;
    z-index: 10;
    overflow: hidden;
    pointer-events: none;
    will-change: left, top, width, height, border-radius, opacity, transform;
  }

  .snapshot-image {
    position: absolute;
    display: block;
    max-width: none;
    max-height: none;
    margin: 0;
    border: 0;
    transform: none;
    will-change: left, top, width, height;
  }

  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }

  :host([data-reduced-motion="true"]) .image,
  :host([data-reduced-motion="true"]) .video,
  :host([data-reduced-motion="true"]) .poster,
  :host([data-reduced-motion="true"]) .video-controls,
  :host([data-reduced-motion="true"]) .close-button {
    transition-duration: 0ms !important;
  }

  :host([data-reduced-motion="true"]) .spinner {
    animation: none;
  }

  @media (forced-colors: active) {
    .video-controls {
      border: 1px solid CanvasText;
    }
  }
`;
