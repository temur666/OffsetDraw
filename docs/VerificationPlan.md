# Verification Plan

## 1. Static Gate

Run:

```text
./scripts/audit_roadmap.py && swiftc -parse OffsetDraw/*.swift
```

Expected result: all checks pass.

## 2. Xcode Build Gate

Run only when explicitly requested:

```text
xcodebuild -project OffsetDraw.xcodeproj -scheme OffsetDraw -configuration Debug -sdk iphonesimulator build
```

Expected result: build succeeds without errors.

## 3. Simulator Gate

Run only when explicitly requested:

- Launch the app in an iPhone simulator.
- Create a drawing.
- Draw one stroke.
- Open More.
- Toggle Brush, Eraser, Layer, Calib. grid, Transparent.
- Return home and confirm the thumbnail updates.

Expected result: no crash, no blank canvas, no missing thumbnail.

## 4. Real Device Gate

Run only on a physical iPhone:

- Follow `docs/DeviceCalibrationChecklist.md`.
- Draw for 5 minutes.
- Record Calibration notes.
- Mark any Issues observed.

Expected result: final hand-feel settings are recorded in the drawing.
