# PageKey

**只在指定 App 前台时，把 macOS 右侧的 Command / Option 临时变成 Page Up / Page Down。切走立刻恢复原样。**

零权限、零内核扩展、零第三方依赖。为「在远程桌面里翻页」这种小事而生。

![platform](https://img.shields.io/badge/macOS-12%2B-blue)
![license](https://img.shields.io/badge/license-MIT-green)
![deps](https://img.shields.io/badge/dependencies-none-brightgreen)
![release](https://img.shields.io/github/v/release/nickeyffff/PageKey)

---

## 这个工具解决什么

在 Windows App（原 Microsoft Remote Desktop）里连远程 Windows 时，右侧的 Command / Option 基本用不上，而 Page Up / Page Down 又天天要用 —— 但 macOS 上遥控器的翻页键在笔记本键盘上得按 `Fn + ↑/↓`，很难受。

于是：**只在那个 App 里**，把两个闲置的右侧修饰键改成翻页键；一离开该 App，它们立刻恢复成正常的 Command / Option。

## 效果

| 场景 | 右 Command | 右 Option |
| --- | --- | --- |
| 目标 App 在前台（默认：Windows App） | `Page Up` | `Page Down` |
| 其他任何 App / 桌面 | 原样，正常的修饰键 | 原样 |

左 Command / 左 Option 全程不受影响。

## 为什么不用现成方案

| 方案 | 问题 |
| --- | --- |
| 系统设置 → 修饰键 | 只能「修饰键 ↔ 修饰键」，映射不到 Page Up / Page Down |
| Karabiner-Elements | 功能强大，但为两个键装驱动 + 系统扩展，且不能真正按 App 隔离到「非修饰键映射」以外的场景也够重 |
| CGEventTap 自研拦截 | 需要「辅助功能」授权；自签名程序的授权记录与二进制哈希绑定，每次重新编译都可能失效 |
| **PageKey（本项目）** | 用系统自带的 `hidutil` 在 App 切换瞬间改写 HID 映射，**完全不需要任何权限** |

## 原理

```
目标 App 激活  ──►  hidutil property --set '{"UserKeyMapping":[右⌘→PgUp, 右⌥→PgDn]}'
目标 App 失活  ──►  hidutil property --set '{"UserKeyMapping":[]}'          （恢复）
程序退出       ──►  同上，清空映射
```

`hidutil` 是 macOS 自带命令（`/usr/bin/hidutil`），直接在 HID 层重映射按键，所以不需要输入监控 / 辅助功能授权。它只有系统级粒度 —— PageKey 的价值就是**替你在正确的时机开关它**。

用到的 HID usage code：

| 键 | usage |
| --- | --- |
| Right Command | `0x7000000E7` |
| Right Option | `0x7000000E6` |
| Page Up | `0x70000004B` |
| Page Down | `0x70000004E` |

## 系统要求

- macOS 12 或更高（在 macOS 27 上验证通过）
- Xcode Command Line Tools（只要 `swiftc`，不需要完整 Xcode）

```bash
xcode-select --install   # 若尚未安装
```

## 安装

### 方式一：一键脚本（推荐）

```bash
curl -fsSL https://github.com/nickeyffff/PageKey/releases/latest/download/install.sh | bash
```

下载最新发布包 → 解压 → 装到 `~/Applications` → **移除 quarantine 隔离属性** → 本地重新签名。
全程不改系统设置、不装后台服务，装完双击即可用。

### 方式二：手动下载安装包

从 [Releases](https://github.com/nickeyffff/PageKey/releases) 下载 `PageKey.dmg`（或 `PageKey.app.zip`），
把 `PageKey.app` 拖进「应用程序」。

### 方式三：源码编译

```bash
git clone https://github.com/nickeyffff/PageKey.git
cd PageKey
make install
```

本机编译出的产物不带 quarantine 标记，**永远不会被 Gatekeeper 拦**，只是需要装 Xcode Command Line Tools。

### 关于「自己打包的应用下载后打不开」

这是 macOS 的 Gatekeeper 机制，不是程序坏了。诚实地列清楚：

| 现象 | 真正原因 | 解决 |
| --- | --- | --- |
| 「已损坏，无法打开，应移到废纸篓」 | 从网络下载的 app 带 `com.apple.quarantine` 扩展属性，且没有 Apple 公证签名 | 用**方式一**；或终端 `xattr -dr com.apple.quarantine /Applications/PageKey.app` |
| 「无法验证开发者」 | 同上（未公证） | 右键点 app → 打开 → 再点「打开」；或到「系统设置 → 隐私与安全性」底部点「仍要打开」 |
| 双击毫无反应 | 可执行文件签名失效 | 用方式一（会本地重签）；或 `codesign --force --sign - /Applications/PageKey.app` |

**为什么不做公证**：走 Apple 公证需要 Developer ID 证书（Developer Program，99 美元/年）并把产物送 Apple 服务器扫描。对一个几百行的键位小工具来说不值当，所以选择：**下载版首次打开手动放行一次，或用一键脚本自动处理**。

## 使用

### 界面

- **启动**：弹说明框，列出当前生效范围与键位映射
- **切到目标 App**：右上角浮出提示条「PageKey 已启用 · Windows App」，2.6 秒淡出
- **菜单栏 ⌨**：查看状态（已启用 / 待命）、勾选「切走时也提示」、手动显示提示条、退出
- **已运行时再双击**：只弹提示，不会起第二个实例

### 命令行

```bash
build/pagekey com.microsoft.rdc.macos        # 指定目标 App
build/pagekey com.apple.Terminal com.foo.bar  # 多个 App 共用同一套映射
build/pagekey com.microsoft.rdc.macos --quiet # 静默启动（不弹说明框，适合登录项）
build/pagekey --list                          # 查当前前台 App 的 bundle id
build/pagekey --reset                         # 清空全局映射，恢复正常
build/pagekey --version
```

| 参数 | 说明 |
| --- | --- |
| `bundle-id ...` | 目标 App，可多个；省略时默认 `com.microsoft.rdc.macos`（Windows App） |
| `--quiet` | 静默启动，不弹启动说明 |
| `--reset` | 清除全局键位映射 |
| `--list` | 打印当前前台 App 及其 bundle id |
| `--version` / `-h` | 版本 / 帮助 |

### 换目标 App

```bash
cd /Applications   # 或切到你想要的 App
~/Applications/PageKey.app/Contents/MacOS/pagekey --list
# 前台 App: Notion  bundle id: notion.id
```

然后用固定参数重新启动：

```bash
~/Applications/PageKey.app/Contents/MacOS/pagekey --quiet notion.id
```

### 开机自启

系统设置 → 通用 → 登录项与扩展 → 添加 `PageKey.app`。

若希望开机时不弹说明框，把登录项改为执行：

```bash
/Users/<你>/Applications/PageKey.app/Contents/MacOS/pagekey --quiet
```

## 已知局限

- **全局 HID 层**：映射是系统级的，切换 App 那一瞬间有毫秒级窗口，理论上可能漏到前后台之间的一次按键。
- **异常退出**：被 `kill -9` 时来不及清理，映射会残留。下次启动会自动清空，也可随时 `--reset` 或 `make reset` 手动恢复。正常退出（⌘Q、菜单退出、SIGTERM）都会清理。
- **右 Command 不再是修饰键**：生效期间无法用它组合快捷键（左 Command 正常可用）。
- **翻页语义随 App 而异**：浏览器 / 预览里是滚动一页，部分编辑器里是移动光标，这与 `Page Up` 键本身的系统行为一致，不是 PageKey 的取舍。
- **与其他改键工具冲突**：`hidutil` 的 `UserKeyMapping` 是单一属性，与 Karabiner 等工具同时使用会互相覆盖。

## 卸载

```bash
cd PageKey
make uninstall    # 删除 App 并清空映射
```

## 开发

```bash
make build    # 只编译 build/pagekey
make app      # 打包 build/PageKey.app（ad-hoc 签名）
make install  # 装到 ~/Applications
make reset    # 清空映射
make clean
```

```
PageKey/
├── Sources/PageKey/main.swift    # 全部逻辑（约 330 行，单文件）
├── Resources/
│   ├── Info.plist                # app bundle 元信息
│   └── AppIcon.icns              # 图标（由 Scripts/make_icon.swift 生成）
├── Scripts/make_icon.swift       # 用 Core Graphics 画图标，改配色后重新生成即可
├── Makefile
└── .github/workflows/build.yml   # CI：编译 + 产物上传
```

重新生成图标：

```bash
swiftc -O Scripts/make_icon.swift -o /tmp/mkicon && /tmp/mkicon /tmp/icon.png
# 再按 16/32/64/128/256/512(+@2x) 导出 iconset，iconutil -c icns 打包
```

代码结构：`HUD`（浮动提示条）→ `AppDelegate`（前台监听、hidutil 调用、菜单栏、弹窗）→ 入口（参数解析、单实例保护）。

## License

[MIT](LICENSE)
