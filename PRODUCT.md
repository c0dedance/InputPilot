# InputPilot

<!-- impeccable:product-schema 1 -->

## Platform

macOS 原生桌面应用（不是 iOS 或网页）。最低 macOS 13。

## Stack

用户确认：Swift、SwiftUI、AppKit、Carbon TIS、ServiceManagement；无第三方依赖。

## Users and Purpose

为希望按应用固定输入法的 Mac 用户提供一个可以本地编译、理解和修改的小工具。用户不熟悉编程，交付必须包含文件说明与一条试玩命令。

## Confirmed Behavior

- 每个应用一条固定输入源规则，支持增删改、启停；无规则保持原状。
- 手动切换保留到下一次进入应用；暂停状态持久化。
- 中文菜单栏状态与独立设置窗口，原生控件，随系统明暗外观。
- 登录启动由用户主动登记，显示系统真实状态。
- 首次无规则，无隐含默认输入源；失败明确报告。
- 全新实现，不读取原软件配置，不复制其代码或资源。

## Boundaries

无网络服务、全局按键监听、辅助功能、输入框识别、符号替换或遥测。一个普通用户进程，无固定轮询。性能和实际输入法兼容性以用户试玩为准，不承诺零 CPU 或低于原软件。
