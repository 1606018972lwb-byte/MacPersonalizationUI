# MacWindowButtons

MacWindowButtons 是一个使用 Swift、AppKit 和 Accessibility API 开发的 macOS 窗口增强工具。它计划在其他应用窗口右上角展示独立的 Windows 风格控制条，用于最小化、最大化或还原、关闭窗口。

## 当前已完成功能

本次提交只完成第一个独立功能：**macOS 菜单栏应用基础结构**。

- 创建标准 AppKit Xcode 工程，最低支持 macOS 13.0。
- 使用 `NSStatusItem` 创建菜单栏入口。
- 提供“启用窗口按钮”“暂停窗口按钮”和“退出”菜单操作。
- 启用与暂停操作具有互斥状态，后续窗口服务可以通过状态回调接入。
- 通过 `LSUIElement` 和 `.accessory` 激活策略隐藏 Dock 图标及 Command + Tab 项目。
- 使用 SF Symbol 显示 Retina 菜单栏图标，并提供符号加载失败时的文本降级方案。

辅助功能权限检查、焦点窗口读取和悬浮控制条尚未在本次提交中实现，它们会作为后续独立功能分别提交。

## 技术方案

核心逻辑使用 AppKit，不把窗口控制能力放入 SwiftUI：

1. `AppDelegate` 只负责应用生命周期和顶层对象组装。
2. `StatusBarController` 负责 `NSStatusItem`、菜单展示和用户操作转发。
3. `ApplicationState` 保存功能启用状态，通过回调与后续窗口服务解耦。
4. 后续使用 `AXUIElement` 获取前台应用焦点窗口，并使用 `AXObserver` 监听窗口变化。
5. 后续使用不抢焦点的透明 `NSPanel` 展示独立悬浮按钮。

## 项目目录

```text
MacWindowButtons/
├── App/
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   └── ApplicationState.swift
Config/
└── Info.plist
MacWindowButtons.xcodeproj/
└── project.pbxproj
```

后续代码将按需求逐步加入 `Accessibility`、`WindowControl`、`Overlay`、`Settings`、`Hotkeys`、`Services`、`Utilities` 和 `Tests` 目录，不提前创建空文件。

## 第一阶段计划

- [x] 创建 Xcode 项目与菜单栏程序。
- [ ] 实现辅助功能权限检查及拒绝授权处理。
- [ ] 获取当前前台应用。
- [ ] 获取当前焦点窗口及基础属性。
- [ ] 完成第一阶段整体编译和手动验证。

每个复选项作为一个独立功能提交，避免把所有功能放在一次提交中。

## Xcode 项目配置

- 平台：macOS
- 最低系统：macOS 13.0
- 语言：Swift 5 兼容模式
- UI 框架：AppKit
- 生命周期：`NSApplicationDelegate`
- Bundle Identifier：`com.lwb.MacWindowButtons`
- Info.plist：手动维护 `Config/Info.plist`
- `Application is agent (UIElement)`：启用
- 签名：Automatic；首次运行前请在 Xcode 的 Signing & Capabilities 中选择自己的 Team

## 编译运行

1. 安装 Xcode 14 或更高版本，并执行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。
2. 使用 Xcode 打开 `MacWindowButtons.xcodeproj`。
3. 在 Target 的 Signing & Capabilities 中选择开发团队。
4. 选择 `My Mac`，执行 Product → Run。
5. 应用启动后不会显示 Dock 图标；请在顶部菜单栏找到窗口图标。

命令行验证：

```bash
xcodebuild -project MacWindowButtons.xcodeproj \
  -scheme MacWindowButtons \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

## 重要限制

- 本程序不会真正移动 macOS 原生红黄绿按钮，而是在窗口右上角显示独立悬浮控制按钮。
- 部分应用可能限制 Accessibility 操作。
- 原生全屏应用中可能无法显示悬浮按钮。
- 开启辅助功能权限后才能控制其他应用窗口。
- 本项目不关闭 SIP、不修改系统文件、不进行进程注入。
- 本项目不能保证兼容所有 macOS 应用。
