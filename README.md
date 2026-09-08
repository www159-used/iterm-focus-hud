# iterm-focus-hud

iTerm2 失焦时：每个可见 iTerm 窗口上盖半透明遮罩 + 居中 dialog 提示；回焦立即消失；点击 iTerm 窗口任意位置回焦并关闭 HUD。

检测用 iTerm2 官方 Focus API；展示用原生 macOS HUD（borderless `NSPanel`，整块遮罩可点击）。不是 Zellij 插件，不污染终端 buffer。

## 结构

```text
LaunchAgent com.ww.focus-hud
  └─ start-all.sh（supervisor，任一挂掉自动重启）
       ├─ focus-hud（原生 HUD daemon）
       └─ python focus_monitor.py（iTerm2 FocusMonitor）
              │
   application_active=false/true │  unix socket JSON
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

- 失焦：给每个 iTerm 窗口盖遮罩（居中卡片仅作视觉提示）。
- **遮罩层级 = 普通，直接排在对应 iTerm 窗口正上方**（`order(.above, relativeTo:)`）：盖住 iTerm 本身，但叠在其上的其它窗口（拖拽、全屏 App）仍在更高 z-order、永不被挡；由窗口服务器自动处理，**无需实时计算**。
- **点击 iTerm 窗口任意位置（遮罩上）→ 激活 iTerm + 关闭 HUD**。
- 回焦：`application_active=true` → 立即 hide。

## 手动调试

```bash
focus-hud                          # daemon 前台运行（或由 LaunchAgent 托管）
focus-hud send '{"cmd":"show","frames":[[100,100,800,600]]}'   # 显示遮罩
focus-hud send '{"cmd":"hide"}'    # 隐藏全部
```

## 协议

unix socket：`~/Library/Application Support/iterm-focus-hud/control.sock`，新行分隔 JSON。

```jsonc
{"cmd":"show","frames":[[x,y,w,h], ...]}   // AppKit 全局屏幕坐标（左下原点，points，直接取 async_get_frame）
{"cmd":"hide"}
```

## 明确不做

- Zellij WASM 插件主路径；往终端 buffer 画假遮罩
- 本功能塞进 agent-board / overview / agent-resume
