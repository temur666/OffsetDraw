#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_TEXT = "\n".join(path.read_text() for path in (ROOT / "OffsetDraw").glob("*.swift"))
DOC_TEXT = (ROOT / "docs" / "ProductExperienceRoadmap.md").read_text()
AUDIT_TEXT = (ROOT / "docs" / "RoadmapImplementationAudit.md").read_text()
CALIBRATION_TEXT = (ROOT / "docs" / "DeviceCalibrationChecklist.md").read_text()
README_TEXT = (ROOT / "README.md").read_text()
VERIFICATION_TEXT = (ROOT / "docs" / "VerificationPlan.md").read_text()


CHECKS = {
    "P1 collapsible workspace": [
        "panelStack.isHidden = true",
        "moreTapped",
        "statusLabel",
        "updateUndoState",
        "Clear this drawing?",
    ],
    "P2 document confidence": [
        "UICollectionViewController",
        "DocumentCell",
        "thumbnailURL",
        "renameDocument",
        "duplicateDocument",
        "deleteDocument",
        "DrawingThumbnails",
        "renderThumbnail",
    ],
    "P3 input calibration": [
        "HandPreset",
        "requiresLongPress",
        "showsCalibrationOverlay",
        "calibrationNotes",
        "CalibrationCheckDTO",
        "calibrationIssuesTapped",
    ],
    "P4 drawing expansion": [
        "StrokeBlendMode",
        "BrushPreset",
        "canvasSizeControl",
        "isTransparentExportEnabled",
        "PHAssetCreationRequest",
        "DrawingLayerDTO",
        "mergeActiveLayerDown",
        "setActiveLayerOpacity",
        "moveActiveLayer",
        "renameActiveLayer",
    ],
    "docs present": [
        "绘画工作台整体性",
        "作品管理可信感",
        "输入手感验证",
        "绘图能力扩展",
    ],
    "audit caveats": [
        "Xcode build",
        "模拟器运行",
        "真机手感确认",
    ],
    "device calibration checklist": [
        "Long Press",
        "Stabilizer",
        "Movement",
        "Smoothing",
        "Guide",
        "Cursor",
    ],
    "codable compatibility": [
        "var blendMode: StrokeBlendMode?",
        "var showsStabilizerGuide: Bool?",
        "var requiresLongPress: Bool?",
        "var layerID: UUID?",
        "var canvas: CanvasConfigDTO?",
        "var layers: [DrawingLayerDTO]?",
        "var activeLayerID: UUID?",
        "var opacity: CGFloat?",
        "var calibration: CalibrationCheckDTO?",
    ],
    "active stroke layering": [
        "private var activeStroke: Stroke?",
        "drawStrokes(activeStroke: activeStroke",
        "if let activeStroke, activeStroke.layerID == layer.id",
        "layerStrokes.append(activeStroke)",
    ],
    "readme current scope": [
        "adaptive thumbnails",
        "collapsible controls",
        "Brush presets",
        "Transparent PNG export",
        "Layer creation",
        "calibration notes",
    ],
    "runtime safeguards": [
        "popoverPresentationController?.sourceView",
        "ensureActiveLayerVisible()",
        "PHAssetCreationRequest.forAsset()",
        "UIImage(contentsOfFile:",
        "try? saveThumbnail(renderThumbnail",
        "previousInteractivePopGestureEnabled",
        "collectionView.backgroundView",
    ],
    "verification plan": [
        "Static Gate",
        "Xcode Build Gate",
        "Simulator Gate",
        "Real Device Gate",
        "DeviceCalibrationChecklist.md",
    ],
    "audit document synchronized": [
        "device calibration checklist：通过",
        "codable compatibility：通过",
        "active stroke layering：通过",
    ],
}


def haystack_for(name: str) -> str:
    if name == "docs present":
        return DOC_TEXT
    if name == "audit caveats":
        return AUDIT_TEXT
    if name == "device calibration checklist":
        return CALIBRATION_TEXT
    if name == "readme current scope":
        return README_TEXT
    if name == "verification plan":
        return VERIFICATION_TEXT
    if name == "audit document synchronized":
        return AUDIT_TEXT
    return SOURCE_TEXT


def main() -> int:
    failed = False
    for name, needles in CHECKS.items():
        haystack = haystack_for(name)
        missing = [needle for needle in needles if needle not in haystack]
        if missing:
            failed = True
            print(f"{name}: MISSING {', '.join(missing)}")
        else:
            print(f"{name}: OK")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
