# OffsetDraw

OffsetDraw is a UIKit iPhone drawing prototype focused on offset-tip slow drawing.

## Current scope

- Document home with adaptive thumbnails
- Create, open, rename, duplicate, and delete drawings
- Full-screen drawing workspace with collapsible controls
- Offset virtual pencil cursor
- Long-press or direct drawing modes
- Stabilizer, movement scale, and smoothing controls
- Brush and eraser tools
- Brush presets and hand-feel presets
- Board color and brush color controls
- Phone, square, and wide canvas ratios
- Transparent PNG export to Photos
- Stroke-based undo
- Layer creation, selection, rename, visibility, reorder, opacity, merge, and delete
- Per-document calibration notes and issue checklist

## Verification

```text
./scripts/audit_roadmap.py
swiftc -parse OffsetDraw/*.swift
```

Xcode build, simulator checks, and real-device hand-feel confirmation are intentionally separate verification steps.
