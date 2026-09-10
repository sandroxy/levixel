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
    -webkit-touch-callout: none;
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

  /* Keep image hit tests on the gesture surface or button. Some mobile
     browsers show their own image menu even after contextmenu is canceled. */
  .image,
  .poster,
  .action-icon img {
    pointer-events: none;
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

  .action-overlay {
    position: absolute;
    inset: 0;
    z-index: 4;
    touch-action: auto;
  }

  .action-backdrop {
    position: absolute;
    inset: 0;
    width: 100%;
    border: 0;
    background: #0007;
  }

  .action-sheet {
    position: absolute;
    bottom: 0;
    left: 0;
    right: 0;
    max-height: 80%;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    outline: none;
    border-radius: 20px 20px 0 0;
    background: #dedede;
    color: #4b5057;
    color-scheme: light;
    font-size: 16px;
    padding: 32px env(safe-area-inset-right) calc(16px + env(safe-area-inset-bottom)) env(safe-area-inset-left);
    overscroll-behavior: contain;
    box-shadow: 0 -8px 40px #0002;
  }

  .action-content {
    min-height: 0;
    overflow-y: auto;
    padding-bottom: 8px;
    overscroll-behavior: contain;
    scrollbar-width: none;
  }

  .action-row {
    display: flex;
    overflow-x: auto;
    min-height: 124px;
    padding: 8px 11px 16px;
    overscroll-behavior: contain;
    scrollbar-width: none;
  }

  .action-content::-webkit-scrollbar,
  .action-row::-webkit-scrollbar { display: none; }

  .action-button {
    flex: 0 0 82px;
    width: 82px;
    border: 0;
    padding: 0 5px;
    background: transparent;
    color: inherit;
    font: inherit;
    cursor: pointer;
  }

  .action-icon {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 60px;
    height: 60px;
    margin: 0 auto 8px;
    border-radius: 16px;
    background: white;
    color: #2f343b;
  }

  .action-icon img {
    position: absolute;
    width: 30px;
    height: 30px;
    object-fit: contain;
  }

  .action-icon-placeholder { font-size: 18px; }

  .action-label {
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    min-height: 32px;
    font-size: 12px;
    line-height: 16px;
    overflow-wrap: anywhere;
  }

  .action-button[data-destructive="true"] { color: #c73934; }
  .action-button:disabled { opacity: .4; cursor: default; }
  .action-button:not(:disabled):active .action-icon { background: #f0f0f0; }

  .action-cancel {
    flex-shrink: 0;
    width: 100%;
    min-height: 56px;
    border: 0;
    border-top: 1px solid #00000012;
    padding: 12px 0;
    background: transparent;
    color: #445f83;
    font: inherit;
    cursor: pointer;
  }

  .action-cancel:active { background: #0000000c; }
  .action-sheet[data-layout="list"] { padding-top: 8px; }
  .action-sheet[data-layout="list"] .action-row {
    display: block;
    overflow: visible;
    min-height: 0;
    padding: 0 24px;
  }
  .action-sheet[data-layout="list"] .action-row + .action-row { margin-top: 8px; }
  .action-sheet[data-layout="list"] .action-button {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    width: 100%;
    min-height: 64px;
    padding: 12px 0;
  }
  .action-sheet[data-layout="list"] .action-button:active { background: #0000000c; }
  .action-sheet[data-layout="list"] .action-button + .action-button { border-top: 1px solid #00000012; }
  .action-sheet[data-layout="list"] .action-label {
    min-height: 0;
    font-size: 16px;
    line-height: 22px;
  }
  .action-sheet[data-layout="list"][data-icons="true"] .action-button {
    justify-content: flex-start;
    text-align: left;
  }
  .action-sheet[data-layout="list"] .action-icon {
    flex: 0 0 24px;
    width: 24px;
    height: 24px;
    margin: 0;
    background: transparent;
    border-radius: 0;
  }
  .action-sheet[data-layout="list"] .action-icon img { width: 24px; height: 24px; }
  .action-sheet button:focus-visible,
  .retry-button:focus-visible { outline: 2px solid #5989ff; outline-offset: -2px; }

  .retry-button {
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -50%);
    padding: 12px 20px;
    border: 1px solid #888;
    border-radius: 10px;
    background: #252525;
    color: white;
    cursor: pointer;
    font: inherit;
  }
  .retry-button[hidden] { display: none; }
`;
