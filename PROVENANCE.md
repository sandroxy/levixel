# Levixel Provenance

## Status

Levixel is an independently maintained SandroX product with its own name,
package identifiers, public API, release process, and substantial original
cross-platform engineering. The current implementation is nevertheless a
derivative work: substantial portions retain a direct code lineage from
Galeria, and the iOS lineage also includes ImageViewer.swift.

It is therefore accurate to describe Levixel as independently maintained and
substantially rewritten. It is not accurate to describe the current codebase
as a clean-room or wholly original implementation.

## Traceable Lineage

- Consolidation source: `https://gitee.com/chrisJxc/native-plugins.git`
- Consolidation snapshot: `3285cc933e04c1772acb4c9e3b5610ae8cee86a5`
- Recorded Galeria import: `908aabb86e4f1b8cfb4ead0046baf8c7210fcbc4`
- Galeria upstream: `https://github.com/nandorojo/galeria`
- ImageViewer.swift upstream: `https://github.com/michaelhenry/ImageViewer.swift`

The audit compared the consolidation snapshot with the current Android and iOS
cores after normalizing product and package renames. Multiple implementation
files remain structurally identical, while the largest viewer and transition
controllers still retain substantial line-level expression from that lineage.
The imported iOS source also carried the ImageViewer.swift MIT notice. Product
renaming, cross-platform ports, new behavior, and extensive later refactors do
not erase that direct source lineage.

The framework-independent runtime under `adapters/web` is implemented against
Levixel's canonical contract and the accepted current native behavior. Earlier
H5 exploration was consulted only as a technical reference; it is neither a
source dependency nor the product authority, and its experimental UI is not
part of the Web runtime. This does not change the repository-wide derivative
classification or the notice policy above.

## Release Policy

- Keep Levixel as the only product and runtime name.
- Preserve `THIRD_PARTY_NOTICES.md` in source distributions and every binary
  artifact that contains Levixel core code.
- Do not remove the upstream notices merely because later revisions add more
  original code.
- Revisit the derivative classification only after a deliberately documented
  clean-room reimplementation by engineers who do not translate the retained
  implementation, followed by a new source-level and history audit.

This file records the engineering provenance audit. It is not legal advice.
