# 走珠笔 Wi-Fi 调参

App 默认打开独立「走珠笔」标签，顶部可切换走珠笔和「两头粗 · 中间细」笔刷。后者在落笔和收笔端保留完整笔宽，中段逐渐收细约 22%。旧的 Delay、Canvas、Works 及文档保持原样。

## 使用

1. 电脑运行本目录的 `启动网页调参.command`，或者在项目根目录执行：

   ```sh
   python3 tools/rollerball-remote/server.py
   ```

2. 电脑浏览器打开 `http://192.168.0.101:18765`。这是默认地址；如果电脑 Wi-Fi IP 不同，网页地址和 App 地址都改成实际 IP。Mac 可用 `ipconfig getifaddr en0` 查看常用 Wi-Fi 接口地址，也可在系统设置查看。电脑本机可打开 `http://127.0.0.1:18765`，但手机不能用这个回环地址。
3. 手机与电脑处于同一 Wi-Fi，在「走珠笔」顶部输入 `192.168.0.101:18765` 或实际地址，点击「连接」。首次允许 App 的本地网络访问；电脑防火墙需要允许 Python 的入站连接。
4. 在网页拖动六个参数或选择墨色。网页显示服务同步结果；App 显示连接状态和已收到参数。约每 0.25 秒读取一次，每笔落笔时锁定参数，下一笔生效。网页中的试画、示例、撤销、清空和 PNG 导出仅作用于网页本地画布。

端口 18765 避开本机已占用的 8765。需要换端口时执行 `python3 tools/rollerball-remote/server.py --port 18766`，同时修改网页地址和 App 输入。默认监听 `0.0.0.0`，只本机测试可加 `--host 127.0.0.1`。终端 Ctrl+C 停止服务。

断开后 App 保留最后一次有效参数，并自动重连；切后台停止请求，回到前台恢复。地址和参数在 App 本地保存。服务的参数只保存在内存，服务重启恢复默认。原生实验画布暂为会话画布，退出进程不保存笔迹，也不会写入旧作品库。

## 实现

- `OffsetDraw/Rollerball/` 是独立 UIKit 画布、纯 Swift 画笔模型、参数客户端和界面，无旧画笔依赖。原生画布为夜间深色，所选墨色自动提亮以保证对比度；双指拖动画布，双指捏合缩放 0.5× 到 4×。
- 原生逻辑点（pt）对应 HTML 的 CSS px，显示像素密度不参与速度/粗细计算。
- 压力 × 默认直径给出基础直径；速度系数为 `0.3 + 0.7 / (1 + (v / speed)^power)`。使用原 HTML 的速度滤波、粗细响应、停笔恢复、圆形印迹间距、离笔积墨；中心线增加轻量自适应平滑，慢写过滤更强，快写缩短延迟。手指使用固定压力，Pencil 对轻压应用柔和曲线；松手时不读取归零压力，中断时不额外积墨。
- `brush.js` 从用户提供的 HTML 提取，保留参考试画算法；`remote.js` 负责串行防抖同步。当前笔画均锁定落笔参数。
- `GET /api/settings` 获取完整参数；`PUT /api/settings` 替换完整参数。JSON 字段：`size, pressure, speed, power, response, pool, color`。笔尖直径默认 8 pt、上限 64 pt；手指固定压力默认 45%，Apple Pencil 以 `max(20%, raw)^0.55` 校准轻压，避免轻触时笔迹过细。网页预览使用同样的压力曲线。严格验证范围、颜色和有限数字；失败不修改状态。
- HTTP 服务仅暴露页面、两份脚本和参数接口。拒绝跨站 Origin 写入；不提供跨域 CORS。用于可信局域网调参，不做公网部署。

## 验证

在项目根目录：

```sh
python3 -m unittest discover -s tools/rollerball-remote -p 'test_*.py'
node --check tools/rollerball-remote/brush.js
node --check tools/rollerball-remote/remote.js
node tests/rollerball-reference.cjs > /tmp/rollerball-reference.json
swiftc OffsetDraw/Rollerball/RollerballEngine.swift OffsetDraw/Rollerball/RollerballRemoteClient.swift tests/RollerballEngineTests.swift -o /tmp/rollerball-engine-tests
/tmp/rollerball-engine-tests /tmp/rollerball-reference.json
xcodebuild -project OffsetDraw.xcodeproj -scheme OffsetDraw -sdk iphonesimulator -configuration Debug -derivedDataPath build/Rollerball CODE_SIGNING_ALLOWED=NO build
```

算法测试执行参考 JavaScript 生成轨迹，再逐点比对 Swift 的半径和积墨；另检查速度上下限、压感、停笔恢复、取消和 IP 校验。接口测试覆盖参数往返、无效输入不改状态、同源写入和静态文件白名单。真实设备的触控延迟、Pencil 压感与最终手感仍需实机确认。
