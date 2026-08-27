# Changelog

## 1.2.0

- Added the first framework-independent Levixel Web runtime.
- Preserved the canonical media, source-hint, source-visibility, and event protocol.
- Added shared source transitions, paging, fit/zoom/pan handoff, vertical dismissal, video controls, lifecycle restoration, accessibility, and reduced-motion handling.
- Preserved the visible preview until a decoded full-resolution image can take over atomically, preventing black flashes during rapid image switching.
- Added bounded source activation so a source can reopen immediately after touch drag dismissal without duplicate activation.
- Added unit checks, artifact-only package checks, and real-Chrome interaction regression coverage.
- Completed interaction acceptance on macOS Chrome, macOS Safari, Android Chrome, and iOS Safari.
