# MacWindowButtons

MacWindowButtons 是一个使用 Swift、AppKit 和 Accessibility API 开发的 macOS 窗口增强工具。它不会修改其他应用的原生标题栏，而是在当前焦点窗口右上角叠加独立的 Windows 风格控制条。

## 当前已完成功能

版本 1.9 已完成可操作的右侧窗口控制条、可视化控制中心和原创应用图标：

- 作为普通前台应用运行，启动后同时显示程序坞图标和 `NSStatusItem` 菜单栏入口。
- 用户点击授权按钮时通过 `AXIsProcessTrustedWithOptions` 请求辅助功能权限。
- 控制中心可以检查权限状态并跳转到系统设置的辅助功能页面。
- 使用 `NSWorkspace` 和 `AXUIElement` 读取当前前台应用及焦点窗口。
- 在焦点窗口右上角显示不抢键盘焦点的半透明 `NSPanel`。
- 按钮从左到右依次为最小化、最大化/还原、关闭。
- 最小化通过写入 `AXMinimized` 实现。
- 关闭通过目标窗口自己的 `AXCloseButton` 执行 `AXPress`，不会强制退出应用。
- 最大化使用窗口所在屏幕的 `visibleFrame`，不会进入 macOS 原生全屏空间；再次点击恢复原始尺寸。
- 使用 200ms 低频定时器跟随窗口移动、缩放、切换和关闭。
- 支持多显示器坐标转换、Retina、浅色和深色模式。
- 不支持某项 AX 操作时，对应按钮自动禁用。
- 启动后在顶部菜单栏显示小图标，点击后打开原生 AppKit 控制中心。
- 菜单栏图标使用系统模板渲染，在蓝色、深色和浅色菜单栏上保持高对比可见。
- 右键菜单栏图标可以打开设置界面、重新启动软件或退出程序。
- 首次双击启动自动显示主界面；应用运行中再次双击或点击程序坞图标也会重新打开并置前。
- 无 Storyboard 启动时显式创建并持有 `AppDelegate`，确保应用生命周期回调和主窗口创建一定执行。
- 使用进程级文件锁保证应用只能运行一个实例；重复启动会唤醒已有实例并打开主界面。
- “重新启动软件”会先退出当前实例，释放单实例锁后再安全启动新进程。
- 启动和刷新时不再反复弹出权限窗口；只有用户主动点击时才请求系统权限。
- “重新授权”可以清理旧临时签名遗留的失效权限记录，并重新请求当前版本权限。
- 权限生效后会自动启用功能、扫描窗口并显示三个控制按钮，无需手动重启。
- 本地 DMG 构建脚本使用稳定的 designated requirement，后续测试版本不再因 cdhash 改变而丢失权限。
- 控制中心可以暂停、启用、检查权限、调整大小或退出应用。
- 缺少权限时右上角显示警告三角图标，控制中心显示橙色警告卡并主动弹出授权说明。
- “按钮大小”提供小、标准、大三档，三个图标和控制条会立即同步缩放。
- 主界面提供“刷新所有程序窗口”，扫描所有运行中的普通应用窗口并显示扫描数量。
- 刷新后会立即在最近使用的目标窗口右上角显示最小化、最大化/还原、关闭三个控件。
- 按钮大小使用 `UserDefaults` 保存，退出或重启后仍保留选择。
- 使用原创深蓝窗口图标，并生成完整的 Retina `AppIcon.icns` 资源。

## 安装与授权

1. 打开 `dist/MacWindowButtons-1.9.dmg`。
2. 将 `MacWindowButtons.app` 拖入 `Applications`。
3. 首次打开未公证测试包时，请右键应用并选择“打开”。
4. 点击顶部菜单栏小图标，在控制中心点击“立即授权”。
5. 前往“系统设置 → 隐私与安全性 → 辅助功能”，开启 MacWindowButtons。
6. 如果列表中已经存在旧版本，请先关闭再重新开启开关；必要时删除旧项目后重新添加 `/Applications/MacWindowButtons.app`。
7. 返回微信并点击微信窗口，右上角应出现三个控制按钮。
8. 如需调整图标大小，在控制中心选择“小 / 标准 / 大”。
9. 右键顶部菜单栏图标，可以打开设置、重新启动或退出程序。
10. 如需重新发现窗口，打开主界面并点击“刷新所有程序窗口”。

从旧的临时签名版本升级时，如果系统设置里的开关显示开启但应用仍提示缺少权限，请点击主界面的“重新授权”，然后在系统设置中重新开启一次。1.9 之后通过项目脚本生成的测试包使用稳定权限身份。

授权后无需反复重启；应用每 200ms 低频检查一次权限和焦点窗口。若按钮仍未出现，点击菜单栏小图标查看控制中心的权限状态。

## 技术方案

核心逻辑使用 AppKit：

1. `AppDelegate` 负责应用生命周期和顶层依赖组装。
2. `StatusBarController` 负责菜单栏小图标、权限警告外观和控制中心窗口。
3. `AccessibilityPermissionManager` 负责权限请求、状态提示和系统设置跳转。
4. `AccessibilityWindowManager` 读取前台应用的 `AXFocusedWindow`，也可扫描所有运行中普通应用的窗口及能力。
5. `OverlayPanelController` 使用非激活 `NSPanel` 定位控制条，并处理主界面触发的全窗口刷新，不抢目标窗口键盘焦点。
6. `WindowActionService` 执行窗口动作，`WindowStateStore` 为每个窗口保存还原尺寸。
7. `ScreenCoordinateConverter` 统一 Accessibility 与 AppKit 坐标系。
8. `AppSettings` 使用 `UserDefaults` 保存大小并通知菜单和悬浮面板刷新。
9. `ControlCenterViewController` 使用纯 AppKit 构建权限、开关、大小、全窗口刷新和退出界面。

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
│   └── ControlCenterViewController.swift
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
- [ ] 使用 `AXObserver` 替换主要轮询并保留低频兼容轮询。
- [ ] 增加应用排除列表和完整设置页面。
- [ ] 增加全局快捷键和开机启动。
- [ ] 增加自动化测试、兼容性测试和正式签名公证。

## Xcode 项目配置

- 平台：macOS
- 最低系统：macOS 13.0
- 语言：Swift 5 兼容模式
- UI 框架：AppKit
- 生命周期：`NSApplicationDelegate`
- Bundle Identifier：`com.lwb.MacWindowButtons`
- `Application is agent (UIElement)`：关闭，应用运行时显示程序坞图标

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
- 本程序是在窗口右上角显示独立悬浮控制按钮，不会修改其他应用代码。
- 部分应用可能限制 Accessibility 属性或操作，对应按钮会被禁用。
- 原生全屏窗口中会隐藏悬浮按钮。
- 开启辅助功能权限后才能读取和控制其他应用窗口。
- 本项目不关闭 SIP、不修改系统文件、不进行进程注入。
- 当前测试 DMG 使用本机临时签名，尚未进行 Developer ID 签名和 Apple 公证。
- 本项目不能保证兼容所有 macOS 应用。
