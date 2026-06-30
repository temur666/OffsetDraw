0. 对话的id

- 未取得。当前环境未提供可用对话 id。

1. 概述

- 按 `docs/ProductExperienceRoadmap.md` 推进 OffsetDraw 的产品体验闭环：将绘画页改为收起式工作台，首页改为缩略图作品入口，补齐重命名、复制、删除、橡皮擦、手感预设、画布比例、透明导出和基础图层。

2. 架构决策

- 主存储继续使用 stroke JSON，缩略图作为派生 PNG 缓存。原因是作品仍需要可恢复编辑，缩略图只负责首页识别。
- 橡皮擦作为带 clear blend mode 的 stroke 保存，不直接破坏历史笔画。这样撤销、保存、导出仍沿用现有 stroke 流程。
- 工作台采用常驻主工具条 + 可收起参数面板，避免将低频参数长期压在画布上。
- 手感预设作为参数组合入口，保留高级滑杆但默认隐藏，降低新用户理解成本。
- 图层先实现最小可编辑闭环：新增、选择、显示/隐藏、删除、按 layerID 保存 stroke。不做合并、重排和透明度，避免把工作台重新拖回复杂面板。
- 引入画布坐标转换，触摸输入、stroke 存储和导出都以配置画布尺寸为基准，不再把 view 坐标直接当成作品坐标。
- 橡皮擦始终在当前图层的 transparency layer 内使用 clear blend mode。这样它只清当前层内容，普通画板会自然露出下方图层或画板背景，透明导出会自然露出透明区域。
- 长按落笔改成可配置项，并进入手感预设。Slow 预设默认关闭长按，给真机手感校准留下直接对照。
- 增加 Calibration 入口，将真机手感记录保存到作品 canvas 配置里。这样 Roadmap 中“真机手感校准”的结果有产品内承载点，而不是只停留在口头验证。
- 图层渲染按 layer 顺序逐层绘制，每层使用独立 transparency layer。橡皮擦只清除当前层内容，不会误擦掉下方图层或画板背景。
- 图层新增 Merge Down，允许把当前层笔画合并到下方图层，补齐基础图层生命周期中“合并”的关键动作。
- 图层补齐重命名、上移/下移和透明度控制，基础图层生命周期不再只停留在新增/删除。
- 增加 Calib. grid 开关，在画布上显示十字线与圆形参考线，用于真机画线时对比滞后、稳定半径和移动倍率。
- 首页增加最小空状态文案 `No drawings`，避免空列表像加载失败，同时不增加说明性废话。
- 将工作台底部动作和图层动作拆成多行等宽按钮，降低小屏横向挤压和文本截断风险。
- 首页缩略图改为自适应网格：窄屏 2 列，中等宽度 3 列，大宽度 4 列，强化“作品入口”而不是“文件列表”的视觉感。
- 首页 collection layout 在初始化阶段直接使用 compositional layout，避免用裸 `UICollectionViewLayout` 作为占位带来的运行期风险。
- 首页空状态改为 `collectionView.backgroundView`，避免额外子视图叠在 collection view 上造成层级和约束干扰。
- 常驻工具条下方增加一行紧凑状态：当前工具、笔宽、当前图层、落笔模式，满足 Roadmap 对“工具状态可见”的要求。
- Undo 现在根据是否存在笔画显示禁用态，避免空作品里常驻动作看起来可执行。
- 透明导出时改用 `PHAssetCreationRequest` 写入 PNG 数据，避免 `UIImageWriteToSavedPhotosAlbum` 在某些路径下丢失 alpha。
- 拆分 Brush 预设和手感 Preset：Brush 只调线宽，Preset 调移动倍率、平滑、稳定半径和长按策略，避免一个预设同时承担两种语义。
- 手感 Preset 应用时保留当前线宽，确保笔刷粗细只由 Brush 预设或 Width 滑杆控制。
- 隐藏当前图层时会自动切到可见图层；如果没有其它可见图层，则保持当前层可见，避免用户在隐藏层上绘制后“笔迹消失”。
- 触摸开始时再次确保当前图层可见，防止通过选择隐藏图层后直接绘制导致新笔画不可见。
- 活动笔画现在插入当前图层的合成顺序中，而不是永远画在所有图层最上方，避免绘制中预览和落笔后的图层层级不一致。
- 图层切换、新增、重命名、移动、合并、删除后同步刷新常驻状态栏，避免状态行显示旧图层名。
- Calibration 增加结构化 Issues 记录，对应 Roadmap 中长按、稳定半径、移动倍率、平滑滞后、引导线干扰、静止笔尖清晰度六个真机观察点。
- 新增 `scripts/audit_roadmap.py`，将 Roadmap 四个优先级的源码证据检查固定成可重复执行的静态审计脚本。
- Issues 入口加入后，动作区重新分配为每行 3 个按钮，避免首行动作过多导致小屏文字压缩。
- Calibration Issues 使用 actionSheet 时设置 popover anchor，避免 iPad 环境下弹窗缺少来源视图导致运行期异常。
- Roadmap 审计脚本新增 Codable 兼容性、真机校准清单、活动笔画图层合成检查，并同步写入 `docs/RoadmapImplementationAudit.md`。
- Roadmap 审计脚本新增审计文档同步性检查，避免脚本覆盖项更新后审计文档遗漏。

3. 变更清单

- `docs/ProductExperienceRoadmap.md`：新增四个优先级的完整产品体验路线文档。
- `OffsetDraw/DrawingModels.swift`：新增 stroke blend mode、稳定器引导显示开关、长按落笔开关、画布配置、手感校准备注、图层 schema 和缩略图路径摘要。
- `OffsetDraw/DrawingDocumentStore.swift`：新增缩略图目录、缩略图保存/懒生成、作品重命名、复制、删除。
- `OffsetDraw/DrawingCanvasView.swift`：新增橡皮擦语义渲染、透明背景导出、画布比例配置、画布坐标转换、图层可见性过滤、稳定器引导显示开关、长按落笔开关、校准网格、缩略图渲染。
- `OffsetDraw/DrawingDocumentStore.swift`：缩略图懒生成与编辑页一致，按图层顺序和层内 clear 语义渲染。
- `OffsetDraw/HomeViewController.swift`：首页由表格改为自适应作品缩略图网格，支持长按菜单重命名、复制和删除，增加最小空状态。
- `OffsetDraw/ViewController.swift`：绘画页改为可收起工作台，新增工具切换、笔刷预设、手感预设、画布比例、基础图层控制、引导开关、校准网格、长按开关、校准记录、透明导出和清空确认。
- `scripts/audit_roadmap.py`：静态核验 Roadmap 四个优先级和审计文档关键 caveat。

4. 当前状态

- 已完成：Roadmap 四个优先级中的产品功能闭环，包括图层最小闭环。
- 已完成：Swift 源码语法解析检查 `swiftc -parse OffsetDraw/*.swift`。
- 未执行：Xcode build、模拟器运行、真机手感验证。用户项目约束要求默认不主动执行完整检查/验证/测试。
- limitation：图层已具备新增、选择、重命名、显示/隐藏、上移/下移、透明度、删除、合并和保存。真机手感校准已有记录入口，但最终手感仍必须由用户在真机实际绘制确认。

5. 下一阶段接续信息

- `DrawingDocumentStore.thumbnailURL(for:)` 固定缩略图路径为 App sandbox 的 `Documents/DrawingThumbnails/{UUID}.png`。
- 首页缺缩略图时会从 JSON stroke 懒生成；真实编辑页保存时会用当前画布配置直接生成更准确的缩略图。
- `BrushConfig.blendMode == .clear` 表示橡皮擦；后续如果加入更多工具，不要把工具类型只塞进按钮状态，应继续进入 stroke schema。
- `CanvasConfigDTO` 当前记录宽高和透明导出开关；编辑页以居中画布显示不同比例，触摸输入会转换为画布坐标。
- 编辑页中透明导出只影响导出/缩略图渲染，不影响正在编辑时的画布底色；否则透明画布会在编辑态变成看不见的空白区域。
- 图层通过 `DrawingLayerDTO` 和 `StrokeDTO.layerID` 关联；旧文件没有 layerID 时会落到 resolved active layer。
- 图层橡皮擦依赖 Core Graphics transparency layer：clear 只清当前层，最后露出下层、画板或透明背景；编辑页、导出和缩略图懒生成使用同一层内清除语义。
- Merge Down 会把当前层 stroke 的 layerID 改成下方图层 id，并删除当前层；这是数据级合并，不会栅格化。
- 图层透明度保存到 `DrawingLayerDTO.opacity`；旧文件默认 opacity = 1。
- 缩略图懒生成按 `CanvasConfigDTO` 的宽高等比映射 stroke，不再使用固定手机屏幕比例。
- 手感预设在 `ViewController.HandPreset` 中定义，应用预设时保留当前颜色和当前工具类型；Slow 预设关闭长按，Precise/Balanced 保留长按。
- `CanvasConfigDTO.calibrationNotes` 保存每个作品的手感校准备注；如果后续要做全局默认值，需要把它从作品配置迁移到 app-level settings。
- `CanvasConfigDTO.calibration` 保存结构化手感问题勾选项；它记录问题是否出现，不替代最终主观判断。
- `showsCalibrationOverlay` 是编辑态临时状态，不持久化；它用于当场真机调参，不属于作品内容。
