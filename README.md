# MacWindowButtons

MacWindowButtons 是一个使用 Swift、AppKit 和 Accessibility API 开发的 macOS 窗口增强工具。它不会修改其他应用的原生标题栏，而是在当前焦点窗口右侧边缘按需展开独立的 Windows 风格控制条。

## 当前已完成功能

正式版本 1.2 在 1.1 基础上优化了设置界面、窗口跟随、窗口外观、启动方式与更新体验：

- 作为 `UIElement` 菜单栏附件应用运行，只显示 `NSStatusItem` 顶部菜单栏入口，不显示程序坞图标。
- 用户点击授权按钮时通过 `AXIsProcessTrustedWithOptions` 请求辅助功能权限。
- 设置窗口采用传统 macOS 偏好设置风格，通过“常规 / 按钮 / 权限 / 更新 / 其他 / 关于”标签分类功能。
- “其他”页可通过下拉框选择“当前悬浮样式”或“与窗口一体”；默认继续使用当前悬浮样式。
- 一体样式使用标题栏材质，移除控制条底部圆角和阴影，并向下覆盖原窗口顶部 5pt，填平两个窗口圆角之间的视觉缺口。
- 切换外观后立即生效并保存；最大化窗口的顶部预留高度会同步校正。
- “常规”页可使用 macOS 13 `SMAppService` 开启登录时自动启动；如果系统需要用户批准，会显示原因并直接打开“登录项”设置。
- “更新”页可同时查询 GitHub 与 Gitee 的最新 Release，单个平台暂时不可用不会影响另一个平台的结果。
- 更新提醒默认开启并默认每 7 天检查，也可选择每天或每 30 天检查，并可随时手动检查。
- 安全自动更新默认开启；只有 DMG 的 SHA-256、Bundle ID、版本和代码签名全部通过验证才会安装，否则停止自动安装并转为人工提示。
- 权限页面可以检查授权状态并跳转到系统设置的辅助功能页面。
- 使用 `NSWorkspace` 和 `AXUIElement` 读取当前前台应用及焦点窗口。
- 在焦点窗口顶部外侧绘制与窗口同宽的半透明控制行，左侧为空白占位区域，三个按钮固定在最右侧。
- 控制条不再自动隐藏，三个按钮始终可以直接点击。
- 使用 `AXObserver` 实时接收移动、缩放和焦点窗口变化事件，不再依赖 200ms 轮询追随。
- 拖动原窗口标题栏时，移动通知会直接更新控制条，不再异步排队或重复扫描焦点窗口。
- 原窗口持续移动期间临时启用最高 120Hz 的 AX 坐标跟踪，鼠标释放后自动停止，兼顾贴合速度与日常功耗。
- 打开本应用设置窗口时临时隐藏外部窗口控制条，避免浮动层级横穿设置界面；切回外部应用后立即恢复定位。
- 在设置界面点击“刷新所有程序窗口”只更新扫描结果，不再强制把最近外部窗口的控制条画在设置窗口上方。
- 拖动控制行左侧空白区域会同步移动目标窗口，操作方式接近 Windows 标题栏。
- 使用本工具最大化窗口时，窗口顶部会主动留出一整行按钮高度，控制条占用预留行而不覆盖标题栏或窗口内容。
- 按钮从左到右依次为最小化、最大化/还原、关闭。
- 最小化通过写入 `AXMinimized` 实现。
- 关闭通过目标窗口自己的 `AXCloseButton` 执行 `AXPress`，不会强制退出应用。
- 最大化使用窗口所在屏幕的 `visibleFrame`，不会进入 macOS 原生全屏空间；再次点击恢复原始尺寸。
- 使用事件通知实时跟随窗口；1 秒低频轮询只作为少数不支持 AX 通知应用的兼容兜底。
- 支持多显示器坐标转换、Retina、浅色和深色模式。
- 不支持某项 AX 操作时，对应按钮自动禁用。
- 启动后在顶部菜单栏显示小图标，点击后打开原生 AppKit 控制中心。
- 菜单栏图标使用系统模板渲染，在蓝色、深色和浅色菜单栏上保持高对比可见。
- 右键菜单栏图标可以打开设置界面、重新启动软件或退出程序。
- 首次双击启动自动显示主界面；应用运行中再次双击或点击顶部菜单栏图标也会重新打开并置前。
- 无 Storyboard 启动时显式创建并持有 `AppDelegate`，确保应用生命周期回调和主窗口创建一定执行。
- 使用进程级文件锁保证应用只能运行一个实例；重复启动会唤醒已有实例并打开主界面。
- “重新启动软件”会先退出当前实例，释放单实例锁后再安全启动新进程。
- 启动和刷新时不再反复弹出权限窗口；只有用户主动点击时才请求系统权限。
- “重新授权”可以清理旧临时签名遗留的失效权限记录，并重新请求当前版本权限。
- 权限生效后会自动启用功能、扫描窗口并显示三个控制按钮，无需手动重启。
- 本地 DMG 构建脚本使用稳定的 designated requirement，后续测试版本不再因 cdhash 改变而丢失权限。
- 设置窗口可以暂停、启用、检查权限、调整大小、刷新窗口或退出应用。
- 缺少权限时右上角显示警告三角图标，控制中心显示橙色警告卡，用户可主动重新授权。
- “按钮大小”提供小、标准、大三档，三个图标和控制条会立即同步缩放。
- 三档按钮的完整点击区域分别扩大为 `38×30`、`46×35`、`54×42 pt`，图标居中但整个矩形均可点击。
- 三个按钮无内边距、无间隙铺满控制条，悬停反馈覆盖完整按钮块。
- 主界面提供“刷新所有程序窗口”，扫描所有运行中的普通应用窗口并显示扫描数量。
- 刷新后会在最近使用的目标窗口右侧短暂展开最小化、最大化/还原、关闭三个控件。
- 按钮大小使用 `UserDefaults` 保存，退出或重启后仍保留选择。
- 使用原创深蓝窗口图标，并生成完整的 Retina `AppIcon.icns` 资源。

## 安装与授权

1. 下载或构建安装包后，打开 `dist/MacWindowButtons-1.2.dmg`。
2. 将 `MacWindowButtons.app` 拖入 `Applications`。
3. 首次打开未公证测试包时，请右键应用并选择“打开”。
4. 点击顶部菜单栏小图标，在设置窗口的“权限”页面点击“重新授权”。
5. 前往“系统设置 → 隐私与安全性 → 辅助功能”，开启 MacWindowButtons。
6. 如果列表中已经存在旧版本，请先关闭再重新开启开关；必要时删除旧项目后重新添加 `/Applications/MacWindowButtons.app`。
7. 返回微信并点击微信窗口，窗口上方会常驻显示一整行；拖动左侧空白区域可以直接移动微信窗口，三个控制按钮位于最右侧。
8. 如需调整图标大小，在设置窗口的“按钮”页面选择“小 / 标准 / 大”。
9. 右键顶部菜单栏图标，可以打开设置、重新启动或退出程序。
10. 如需重新发现窗口，打开主界面并点击“刷新所有程序窗口”。
11. 如需开机启动，在“常规”页勾选“登录时自动启动”；若出现橙色提示，请按按钮进入系统设置批准登录项。
12. 在“更新”页可以设置检查周期、手动检查及自动安装。自动安装完成后应用会自动重启。
13. 在“其他”页选择“与窗口一体”，可以取消控制条下方圆角与阴影，让它更像原窗口的一部分。

从旧的临时签名版本升级时，如果系统设置里的开关显示开启但应用仍提示缺少权限，请点击主界面的“重新授权”，然后在系统设置中重新开启一次。1.9 之后通过项目脚本生成的测试包使用稳定权限身份。

授权后无需反复重启；应用通过系统事件即时跟随窗口，并使用 1 秒轮询兼容少数不发送事件的应用。若按钮仍未出现，点击菜单栏小图标查看控制中心的权限状态。

## 技术方案

核心逻辑使用 AppKit：

1. `AppDelegate` 负责应用生命周期和顶层依赖组装。
2. `StatusBarController` 负责菜单栏小图标、权限警告外观和控制中心窗口。
3. `AccessibilityPermissionManager` 负责权限请求、状态提示和系统设置跳转。
4. `AccessibilityWindowManager` 读取前台应用的 `AXFocusedWindow`，也可扫描所有运行中普通应用的窗口及能力。
5. `OverlayPanelController` 使用非激活 `NSPanel` 定位控制条，并处理主界面触发的全窗口刷新，不抢目标窗口键盘焦点。
6. `WindowActionService` 执行窗口动作，`WindowStateStore` 为每个窗口保存还原尺寸。
7. `ScreenCoordinateConverter` 统一 Accessibility 与 AppKit 坐标系。
8. `AppSettings` 使用 `UserDefaults` 保存按钮大小、更新开关、检查周期和上次检查时间。
9. `LaunchAtLoginController` 通过 `SMAppService.mainApp` 注册登录项并处理系统批准状态。
10. `UpdateManager` 查询 GitHub/Gitee Release、比较语义版本，并负责经过安全校验的 DMG 更新流程。
11. `ControlCenterViewController` 使用纯 AppKit 构建常规、按钮、权限、更新和关于页面。

## 项目目录

```text
MacWindowButtons/
├── App/
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   └── ApplicationState.swift
├── Accessibility/
│   ├── AccessibilityPermissionManager.swift
│   ├── AccessibilityWindowManager.swift
│   └── AXElementExtensions.swift
├── WindowControl/
│   ├── TargetWindow.swift
│   ├── WindowActionService.swift
│   ├── WindowStateStore.swift
│   └── ScreenCoordinateConverter.swift
├── Overlay/
│   ├── OverlayPanelController.swift
│   ├── WindowButtonsView.swift
│   └── WindowControlButton.swift
├── Settings/
│   ├── AppSettings.swift
│   ├── ControlCenterViewController.swift
│   ├── LaunchAtLoginController.swift
│   └── UpdateManager.swift
├── Resources/
│   └── Assets.xcassets/AppIcon.appiconset/
└── Design/
    └── AppIcon-master.png
```

## 开发进度

- [x] 创建 Xcode 项目与菜单栏程序。
- [x] 实现辅助功能权限检查及拒绝授权处理。
- [x] 获取当前前台应用和焦点窗口基础属性。
- [x] 创建右上角悬浮控制条。
- [x] 实现最小化、最大化/还原和关闭。
- [x] 实现基础多显示器坐标转换。
- [x] 增加菜单栏按钮大小设置与持久化。
- [x] 增加菜单栏控制中心、点击授权提示和原创应用图标。
- [x] 增加主界面全窗口刷新、扫描结果提示和三控件立即显示。
- [x] 使用 `AXObserver` 替换主要轮询并保留低频兼容轮询。
- [x] 增加按功能分类的完整偏好设置页面。
- [ ] 增加应用排除列表。
- [x] 增加开机启动、双平台更新提醒和安全自动更新。
- [ ] 增加全局快捷键。
- [ ] 增加自动化测试、兼容性测试和正式签名公证。

## Xcode 项目配置

- 平台：macOS
- 最低系统：macOS 13.0
- 语言：Swift 5 兼容模式
- UI 框架：AppKit
- 生命周期：`NSApplicationDelegate`
- Bundle Identifier：`com.lwb.MacWindowButtons`
- `Application is agent (UIElement)`：启用，应用运行时不显示程序坞图标

命令行构建：

```bash
xcodebuild -project MacWindowButtons.xcodeproj \
  -scheme MacWindowButtons \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

生成带稳定本地签名要求的测试 DMG：

```bash
./Scripts/build-dmg.sh
```

## 重要限制

- macOS 不允许普通应用稳定移动微信等程序的原生红黄绿按钮；左侧原生按钮仍会保留。
- 本程序是在窗口右侧边缘显示独立悬浮控制按钮，不会修改其他应用代码。
- 部分应用可能限制 Accessibility 属性或操作，对应按钮会被禁用。
- 原生全屏窗口中会隐藏悬浮按钮。
- 开启辅助功能权限后才能读取和控制其他应用窗口。
- 本项目不关闭 SIP、不修改系统文件、不进行进程注入。
- 当前测试 DMG 使用本机临时签名，尚未进行 Developer ID 签名和 Apple 公证。
- 自动更新要求 Release 正文包含对应 DMG 的 64 位 SHA-256；缺少校验值时只显示更新提醒，不会静默安装。
- 应用安装目录不可写时无法无感替换，请从发行页面手动安装；正式分发仍建议配置 Developer ID 签名、公证和专用更新框架。
- 本项目不能保证兼容所有 macOS 应用。
