# Roadmap Implementation Audit

## 1. Scope

本审计对应 `docs/ProductExperienceRoadmap.md` 的四个优先级：

- 绘画工作台整体性
- 作品管理可信感
- 输入手感验证
- 绘图能力扩展

审计依据为当前源码和允许范围内的 Swift 语法核验。未包含 Xcode build、模拟器运行和真机手感结论。

## 2. Priority 1: 绘画工作台整体性

状态：已实现。

证据：

- 绘画页使用常驻主工具条和可收起参数面板。
- 参数面板默认收起。
- 常驻状态行显示当前工具、笔宽、当前图层和落笔模式。
- Undo 在无笔画时显示禁用态。
- Clear 和 Delete Layer 均有二次确认。
- 底部动作与图层动作拆成多行等宽按钮，降低小屏横向挤压风险。

主要文件：

- `OffsetDraw/ViewController.swift`
- `OffsetDraw/DrawingCanvasView.swift`

## 3. Priority 2: 作品管理可信感

状态：已实现。

证据：

- 首页由表格列表改为自适应作品缩略图网格。
- 首页支持重命名、复制、删除。
- 首页有最小空状态。
- 缩略图保存为派生 PNG 缓存，主存储仍是 stroke JSON。
- 缩略图缺失时可从文档懒生成。
- 编辑页保存时同步更新缩略图。

主要文件：

- `OffsetDraw/HomeViewController.swift`
- `OffsetDraw/DrawingDocumentStore.swift`
- `OffsetDraw/ViewController.swift`

## 4. Priority 3: 输入手感验证

状态：产品内闭环已实现；真机主观结论待实机确认。

证据：

- 提供 Precise、Balanced、Slow 三个手感预设。
- 稳定半径、移动倍率、平滑程度仍可细调。
- 稳定器引导线可开关。
- 长按落笔可开关，Slow 预设默认关闭长按。
- 画布校准网格可开关。
- Calibration 入口可保存每个作品的手感备注。
- Calibration Issues 可结构化记录六个真机观察点：长按、稳定半径、移动倍率、平滑滞后、引导线干扰、静止笔尖清晰度。

主要文件：

- `OffsetDraw/ViewController.swift`
- `OffsetDraw/DrawingCanvasView.swift`
- `OffsetDraw/DrawingModels.swift`

说明：

- Roadmap 中“真机画 5 分钟”的动作必须由真机实际操作完成。当前实现已经提供记录和对照工具，但不能替代真实手感判断。
- 真机校准执行清单见 `docs/DeviceCalibrationChecklist.md`。

## 5. Priority 4: 绘图能力扩展

状态：已实现。

证据：

- 橡皮擦作为 clear stroke 保存，并在每层 transparency layer 内生效。
- Brush 预设独立于手感预设，只控制线宽。
- 支持 Phone、Square、Wide 三种画布比例。
- 支持透明背景导出；透明导出写入 PNG 数据以保留 alpha。
- 图层支持新增、选择、重命名、显示/隐藏、上移/下移、透明度、删除、合并和保存。
- 图层渲染按层顺序执行，橡皮擦只清当前层。

主要文件：

- `OffsetDraw/DrawingModels.swift`
- `OffsetDraw/DrawingCanvasView.swift`
- `OffsetDraw/ViewController.swift`
- `OffsetDraw/DrawingDocumentStore.swift`

## 6. Verification

已执行：

```text
swiftc -parse OffsetDraw/*.swift
```

结果：通过。

已执行源码条目核验：

```text
python3 scripts/audit_roadmap.py
```

- P1 collapsible workspace：通过
- P2 document confidence：通过
- P3 input calibration：通过
- P4 drawing expansion：通过
- docs present：通过
- audit caveats：通过
- device calibration checklist：通过
- codable compatibility：通过
- active stroke layering：通过

人工条目对应：

- P1 收起式工具栏：通过
- P1 工具状态可见：通过
- P1 危险动作确认：通过
- P2 缩略图首页：通过
- P2 文件操作：通过
- P2 缩略图派生缓存：通过
- P3 手感校准：通过
- P3 稳定器可调：通过
- P4 橡皮擦：通过
- P4 笔刷预设：通过
- P4 画布比例/透明导出：通过
- P4 图层：通过

未执行：

- Xcode build
- 模拟器运行
- 真机手感确认

原因：项目约束要求默认不主动执行完整检查/验证/测试，除非用户明确要求。
