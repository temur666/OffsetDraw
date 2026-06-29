0. 对话的id

- 未取得。`/home/tiemuer/.gemini/antigravity/brain` 不存在。

1. 概述

- 将 OffsetDraw 从单画布原型推进为文件化画画本：只保留长按绘制，增加主页新建/打开文件、画笔颜色、画板颜色，并把笔画与配置持久化到 App Documents 目录。

2. 架构决策

- 采用 Documents/Drawings 下的单 JSON 文件保存每个画画本，不使用图片快照作为主存储。原因是笔画、画笔配置、画板配置都需要可恢复和可继续编辑，JSON stroke schema 比 PNG 更适合当前阶段。
- 首页只做文件列表与新建入口，不做缩略图。缩略图需要额外渲染缓存和失效策略，当前闭环的核心是文件生命周期与恢复编辑。
- 颜色选择使用系统 UIColorPickerViewController，不自建色板。这样可以先获得完整颜色能力，同时避免新增一套颜色 UI 状态。
- 保存策略为自动保存：每笔结束、撤销、清空、颜色变化、画笔参数变化都会写回文件。

3. 变更清单

- 新增 `OffsetDraw/DrawingDocumentStore.swift`：负责 Documents/Drawings 目录、文件列表、新建、读取、保存。
- 新增 `OffsetDraw/HomeViewController.swift`：主页文件列表与新建文件入口。
- 修改 `OffsetDraw/DrawingModels.swift`：新增 Codable 文档 schema、颜色 DTO、笔画 DTO、文件摘要模型；删除多绘制模式 enum。
- 修改 `OffsetDraw/DrawingCanvasView.swift`：删除 Button / Double 两种绘制模式，只保留长按；新增画板颜色、文档加载、变更回调。
- 修改 `OffsetDraw/ViewController.swift`：接入文档加载/保存，新增画笔颜色和画板颜色按钮，配置变化自动持久化。
- 修改 `OffsetDraw/SceneDelegate.swift`：启动入口改为 UINavigationController + HomeViewController。
- 修改 `OffsetDraw.xcodeproj/project.pbxproj`：把新增 Swift 文件加入 target sources。

4. 当前状态

- 已完成：主页、新建文件、打开文件、长按绘制、画笔颜色、画板颜色、笔画与配置 JSON 持久化。
- 已完成：清理第二/第三绘制模式相关入口和逻辑。
- 未执行：Xcode build 或模拟器验证。用户本轮未要求检查/验证/测试。
- limitation：主页暂不显示缩略图；文件暂不支持重命名、删除、复制。

5. 下一阶段接续信息

- 文档文件路径由 `DrawingDocumentStore` 固定为 App sandbox 的 `Documents/Drawings/{UUID}.json`。
- `DrawingCanvasView.onDocumentChanged` 是画布向编辑页通知保存的唯一出口，当前在结束一笔、撤销、清空时触发。
- 颜色配置直接保存 RGBA，不保存 UIColor 原始对象，避免 UIKit 类型参与 JSON 编码。
- `loadDocument()` 会同步 canvas、slider label、颜色按钮 tint；以后新增可持久化配置时，需要同时更新文档 schema、加载映射和 `persistDocument()`。
