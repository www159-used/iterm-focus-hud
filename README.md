# iterm-focus-hud

按独立窗口显示焦点：当前聚焦窗口无遮罩，其他可见 iTerm2 窗口显示浅遮罩和居中提示；切到其他应用后，所有可见窗口显示深色遮罩和相同的居中提示。点击遮罩可激活对应窗口。

检测用 iTerm2 官方 Focus API；展示用原生 macOS HUD（borderless `NSPanel`，整块遮罩可点击）。不是 Zellij 插件，不污染终端 buffer。

## 结构

```text
LaunchAgent com.ww.focus-hud
  └─ start-all.sh（supervisor，任一挂掉自动重启）
       ├─ focus-hud（原生 HUD daemon）
       └─ python focus_monitor.py（iTerm2 窗口焦点同步）
              │
   窗口焦点与几何状态           │  unix socket JSON
              ▼                  ▼
        原生 HUD：半透明遮罩 + 居中卡片
```

| 目录       | 职责                                   |
|-----------|----------------------------------------|
| `HUD/`    | Swift 包：`FocusHUD` 可执行程序（daemon + `send` 客户端） |
| `iterm/`  | `focus_monitor.py` 失焦检测脚本（由 supervisor 运行，不依赖 iTerm AutoLaunch） |
| `scripts/`| supervisor / LaunchAgent plist         |
| `Makefile`| 一键安装 / 卸载 / 状态                 |

## 安装

```bash
make install      # 构建 + 检测 Python Runtime + 部署 + LaunchAgent 自启（一条命令）
make status       # 查看 HUD daemon / 检测进程 / socket
make uninstall    # 卸载
```

`make install` 会自动检测 iTerm2 Python Runtime；未就绪会提示去 iTerm2 → Scripts → Install Python Runtime 安装后重试。

前提：iTerm2 需安装 Python Runtime（菜单 Scripts → Install Python Runtime，或首次运行脚本时按提示安装）。

## 行为细节

- iTerm2 内切换独立窗口：当前窗口无遮罩，其余窗口显示 18% 黑色浅遮罩和居中提示卡。
- 切到其他应用：可见 iTerm2 窗口显示 35% 黑色遮罩和居中提示卡。
- 两种遮罩统一显示「iTerm 已失焦」和「点击任意处返回」。
- 约每 200ms 同步焦点和窗口位置；启动或 HUD 重启后自动同步，无需先切换焦点。
- **遮罩层级 = 普通，直接排在对应 iTerm 窗口正上方**（`order(.above, relativeTo:)`）：盖住 iTerm 本身，但叠在其上的其它窗口（拖拽、全屏 App）仍在更高 z-order、永不被挡；由窗口服务器自动处理，**无需实时计算**。
- **点击遮罩 → 通过 iTerm2 API 激活对应独立窗口**；其余窗口继续显示浅遮罩。
- 仅为当前在屏且能匹配的窗口创建遮罩，最小化或其他桌面的窗口不创建悬空遮罩。窗口矩形完全重合、无法唯一匹配时暂不显示遮罩，避免遮住或激活错误窗口。
- Tab 和分屏 pane 不分别加遮罩。

## 手动调试

```bash
focus-hud                          # daemon 前台运行（或由 LaunchAgent 托管）
focus-hud send '{"cmd":"show","frames":[[100,100,800,600]]}'   # 显示遮罩
focus-hud send '{"cmd":"hide"}'    # 隐藏全部
```

## 协议

unix socket：`~/Library/Application Support/iterm-focus-hud/control.sock`，新行分隔 JSON。
点击请求通过同目录的 `activate.sock` 发送 `{"windowID":"..."}` 给 Python monitor，再调用窗口与应用的激活 API。参见 [iTerm2 Window API](https://iterm2.com/python-api/window.html)。

```jsonc
{"cmd":"show","windows":[{"windowID":"pty-...","frame":[x,y,w,h]}],"subtle":true}
{"cmd":"show","frames":[[x,y,w,h], ...]}   // AppKit 全局屏幕坐标（左下原点，points，直接取 async_get_frame）
{"cmd":"hide"}
```

## 明确不做

- Zellij WASM 插件主路径；往终端 buffer 画假遮罩
- 本功能塞进 agent-board / overview / agent-resume

## License

GNU Affero General Public License v3.0 (AGPL-3.0) — 见 [LICENSE](LICENSE)。

## 验证

```bash
python3 -m unittest discover -s tests -v
make build
```
