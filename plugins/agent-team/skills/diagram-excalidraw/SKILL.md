---
name: diagram-excalidraw
description: Generate editable .excalidraw architecture and flow diagrams from the codebase or a design, with a self-review pass for layout problems. Use when a system's shape is easier to show than to describe.
when_to_use: Documenting architecture, request flows, data models, or state machines. Do NOT use when a short list or table would carry the same information.
---

# Excalidraw diagrams

A diagram earns its place when it shows a **mechanism** — how things move,
where they cross a boundary, what depends on what. A diagram that merely lists
components in boxes is a worse table; write the table instead.

## Before drawing

Decide the one question the diagram answers. Write it as the title. If you
cannot state it, you are not ready to draw.

Good: "How a request reaches the database and what it crosses on the way."
Bad: "System architecture."

## File format

Excalidraw files are JSON:

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "agent-team",
  "elements": [],
  "appState": { "viewBackgroundColor": "#ffffff", "gridSize": null }
}
```

Every element needs `id`, `type`, `x`, `y`, `width`, `height`, `angle`,
`strokeColor`, `backgroundColor`, `fillStyle`, `strokeWidth`, `roughness`,
`opacity`, `seed`, `version`, `versionNonce`, `isDeleted`, `groupIds`,
`boundElements`, `updated`, `link`, `locked`.

**Labels**: bind text to a shape by setting the text element's `containerId` to
the shape's id, and adding `{"id": "<textId>", "type": "text"}` to the shape's
`boundElements`. Unbound text drifts when the shape moves.

**Arrows**: bind endpoints with `startBinding` / `endBinding`
(`{"elementId": "...", "focus": 0, "gap": 8}`), and add the arrow to both
shapes' `boundElements`. Unbound arrows detach on edit — this is the single most
common defect in generated diagrams.

## Layout

- Flow left-to-right or top-to-bottom. Pick one and hold it.
- Minimum 60px between boxes. Crowding reads as noise.
- Align on a grid — mismatched coordinates look accidental.
- Group related nodes inside a labelled rectangle for boundaries (service,
  process, trust zone).

## Colour with meaning

Colour must encode something, or be absent. Assign one meaning and state it in
a legend: e.g. blue = our code, grey = third party, red = trust boundary
crossing. Decorative colour makes the reader hunt for a pattern that is not there.

## Self-review before delivering

Re-read the generated JSON and check:

- [ ] Every arrow has both `startBinding` and `endBinding`
- [ ] Every label has `containerId` and appears in its container's `boundElements`
- [ ] No overlapping boxes (compare x/y/width/height pairwise)
- [ ] Text fits its container — long labels overflow silently
- [ ] Every `id` is unique
- [ ] The title states the question the diagram answers

If a rendering tool is available, render and look at it. Reading JSON is a poor
substitute for seeing overlapping text.

## Keeping it true

A stale diagram is worse than none, because it is believed. Note the commit it
describes, and regenerate it when the structure changes.
