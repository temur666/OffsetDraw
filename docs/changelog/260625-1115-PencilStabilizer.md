0. 对话的id
- 未获取

1. 概述
- 为 OffsetDraw 增加静态铅笔笔尖、长按落笔和拉绳稳定器，让手指负责牵引，笔尖负责稳定落线。

2. 架构决策
- 选择显式状态机区分 idle、waitingLongPress、hoveringTip、drawing，避免触摸事件直接等同于落笔。
- 放弃低通百分比平滑，改为专业绘画软件常见的拉绳稳定器：手指目标点在稳定半径内时笔尖不动，超过半径后才牵引笔尖。
- 铅笔笔尖作为独立 cursor 状态常驻画布，不在 touchesBegan 时跳到手指位置，减少第一次触摸带来的位置突变。

3. 变更清单
- OffsetDraw/DrawingModels.swift：BrushConfig 新增 stabilizerRadius，默认 40pt。
- OffsetDraw/DrawingCanvasView.swift：新增铅笔笔尖绘制、0.5 秒静止长按、长按进度环、拉绳稳定线、目标点和笔尖分离逻辑。
- OffsetDraw/ViewController.swift：底部工具栏改为按钮和控制两行，新增稳定半径滑杆，范围 0...120pt。
- OffsetDraw/Info.plist 与 OffsetDraw.xcodeproj/project.pbxproj：使用显式 Info.plist，保留照片导出权限和 Scene 配置。

4. 当前状态
- 已完成铅笔常驻显示，首次默认在画布中心偏上，清空和抬手后不隐藏。
- 已完成 0.5 秒静止长按才开始绘画；长按前移动只牵引笔尖，不保存笔迹。
- 已完成拉绳稳定器可视反馈：蓝色虚线连接手指目标点和铅笔笔尖，目标点以小圆点显示。
- 已通过 iOS Simulator Debug 构建验证。

5. 下一阶段接续信息
- 需要真机验证稳定半径默认值 40pt 是否合适；半径过大线会更稳但笔尖滞后明显。
- 当前长按判定仍基于手指目标点相对按下点的 8pt 容忍半径，稳定器不会放宽长按静止要求。
- 如果后续加入颜色、橡皮擦或图层，落笔数据仍应沿用 Stroke 数据结构，不要直接只写位图。
