# Bunny Can Bite

**Bunny Can Bite** 是本开源仓库的名称；它提供的 Mac 应用仍叫 **Memory Glass**。

Memory Glass 是原生 macOS 内存监测工具，为 Apple Silicon Mac 设计。SwiftUI、AppKit 与 Charts 构建界面，Darwin VM 和 libproc 提供本机实时数据。无需浏览器、服务器、运行时依赖或联网。

## 功能

- **菜单栏常驻**：实时显示内存使用百分比；启动后默认不打开窗口，也不占用 Dock。
- **毛玻璃浮层**：点击菜单栏图标查看总体内存状态，以及占用内存最多的前 10 个应用。完整面板可以从浮层打开。
- **完整面板**：内存概览、应用与进程明细、搜索排序、进程展开和最近 30 分钟趋势；支持 1、2、5 秒采样间隔。
- **登录时启动**：通过 macOS 原生 `SMAppService` 注册，显示系统实际状态，支持关闭和跳转系统设置。安装器不创建登录项；应用首次打开时处理注册。
- **强制退出**：浮层每个应用右侧可直接发起，确认应用名称、固定进程列表和未保存内容提示后执行；结果在浮层内显示，无需打开完整面板。完整面板仍支持单个进程退出。保护关键系统进程与自身，不提升权限。
- **状态可见**：暂停、采样错误和数据过期会明确标记。关闭完整面板仍继续采样，完全退出应用才停止。

应用数据和历史仅保存在本机内存中，退出后不会保留。登录项选择由本机设置保存。

## 安装与使用

源码和安装包公开发布在 [Bunny Can Bite](https://github.com/xiematt125-dotcom/Bunny-Can-Bite)，查看源码和下载安装包无需登录 GitHub。每次应用更新都会同步源码，并在 [Releases](https://github.com/xiematt125-dotcom/Bunny-Can-Bite/releases/latest) 发布对应版本的 PKG、DMG 与 SHA256 校验文件。

当前版本 **Memory Glass 1.3.2**：

- [下载 PKG 安装包](https://github.com/xiematt125-dotcom/Bunny-Can-Bite/releases/download/v1.3.2/MemoryGlass-1.3.2-arm64.pkg)（推荐，使用 Mac 原生安装器）。
- [下载 DMG 安装包](https://github.com/xiematt125-dotcom/Bunny-Can-Bite/releases/download/v1.3.2/MemoryGlass-1.3.2-arm64.dmg)（拖动安装）。
- [查看发布说明及校验文件](https://github.com/xiematt125-dotcom/Bunny-Can-Bite/releases/tag/v1.3.2)。

需要 **Apple Silicon（M 系列芯片）与 macOS 14 或更新版本**。当前产物仅包含 `arm64`，不支持 Intel Mac。

两种安装方式任选其一：

1. 打开 `MemoryGlass-1.3.2-arm64.pkg`，使用 macOS 安装器安装到 `/Applications`。
2. 打开 `MemoryGlass-1.3.2-arm64.dmg`，将 `Memory Glass.app` 拖入 `Applications`。

升级前先从菜单栏退出旧版，再覆盖安装。安装后从“应用程序”打开一次 Memory Glass；以后从菜单栏查看数据。请保留并运行安装目录中的一份应用，避免从下载目录或磁盘映像启动另一份。

首次从 `/Applications` 打开应用时，会尝试开启登录时启动。该首次配置只尝试一次，之后尊重你手动关闭的选择。登录项由系统管理；如果状态提示“需要批准”，可通过应用内入口打开“系统设置 → 通用 → 登录项与扩展”批准。系统拒绝或关闭登录项时，应用会显示实际状态，不把注册请求当作已开启。

### 签名与公证

默认构建使用 **ad-hoc 应用签名**；分发包没有 Developer ID / Developer ID Installer 签名，**未经 Apple 公证**。下载到其他 Mac 后可能触发 Gatekeeper 提示；请确认来源可信，再按 macOS“隐私与安全性”中的允许打开流程操作。不要关闭系统安全防护。

公开下载的当前安装包使用上述签名方式。需要提供无额外提示的安装体验时，应使用 Apple Developer 身份签名并完成公证。

### 卸载

先在应用中关闭“登录时启动”，从菜单栏完全退出，然后将 `/Applications/Memory Glass.app` 移到废纸篓。应用不安装独立守护进程、LaunchAgent 或安装后脚本。

## 源码构建

安装 Xcode 或 Xcode Command Line Tools，确认 `xcrun swiftc --version` 可运行。在源码目录执行：

```sh
./build.sh
```

应用生成于 `dist/Memory Glass.app`。第一个参数可指定输出目录：

```sh
./build.sh ./dist-preview
```

脚本优先选择 macOS 26.5 SDK，若未安装则使用当前 macOS SDK。原因是部分 Command Line Tools 的 macOS 27 SDK 缺少 SwiftUI 所需的宏插件；完整 Xcode 中的兼容 SDK 也可以使用。最低部署版本始终为 macOS 14。使用 `SDKROOT` 显式选择 SDK 名称或绝对路径：

```sh
SDKROOT=macosx ./build.sh
```

构建先在临时目录完成编译和签名验证，再替换输出应用。重新构建前请退出输出目录中的旧版应用。

## 创建安装包

```sh
./package.sh
```

脚本先构建应用，再生成 `dist/MemoryGlass-<版本>-arm64.pkg` 和 `.dmg`。也可打包已构建并通过签名验证的应用：

```sh
./package.sh ./dist-packages './dist/Memory Glass.app'
```

使用系统自带的 `pkgbuild`、`hdiutil` 和 `codesign`，无需额外包管理器。安装包固定安装到 `/Applications`，禁止自动重定位到开发副本；覆盖升级时保留目录外的设置。打包过程不安装应用、不注册登录项，也不运行应用。安装包不包含安装前后脚本。

## 验证

```sh
./Tests/run-tests.sh
```

测试覆盖 VM 计数数学、应用分组与父子关系、不可读进程保留、真实采样，以及强退保护、过期进程身份、权限和信号错误、退出确认、去重与组隔离。也验证浮层前 10 个应用的排序、菜单栏状态，以及使用模拟服务的登录项状态转换。浮层退出测试覆盖固定目标、取消零执行、单次提交、跨界面结果隔离、关闭重开后的结果保留和系统保护。强退集成测试仅创建并结束测试自己启动的 `/bin/sleep` 子进程；登录项测试不会注册真实登录项。

可单独打印一份真实快照辅助本机诊断：

```sh
./.build/tests/collector-tests --json
```

快照可能包含本机程序名和可执行文件路径，应用不会上传；请勿把未检查的快照提交到公开仓库。

菜单栏、浮层、登录项及关闭/重新打开面板的行为需在真实 macOS 图形会话中验证。`pkgutil --expand-full` 可检查安装包内容，`hdiutil verify` 可检查磁盘映像。

## 数据口径与限制

总体使用率按原生 VM 计数计算。应用内存优先读取 physical footprint，读取失败时使用 RSS 并标记；系统保护导致无法读取的数据明确显示为不可用。各进程和共享内存的统计口径不同，因此应用占用之和不保证等于系统总体使用量。

强退会丢失目标程序未保存的内容。确认目标锁定 PID 与进程启动时间，执行前再次核对；不会把后续新增进程自动加入已确认列表。不使用 `sudo`，系统不允许退出的进程会报告失败。公开、非特权的 `kill(2)` 无法与进程身份检查组成原子操作，因此极短的 PID 复用竞态仍无法完全消除。

## 目录

```text
Sources/      原生 UI、采样、登录项和强退实现
Resources/    应用图标
Tests/        采样与强退回归测试
docs/         安装说明
build.sh      编译与 ad-hoc 签名
package.sh    PKG 与 DMG 分发包
LICENSE       MIT 许可证
```

## 许可证

本项目采用 [MIT 许可证](LICENSE)，版权归 **Bunny Can Bite contributors**。允许使用、修改、分发和商用，分发时须保留版权声明和许可声明；软件按原样提供，不作担保。安装包内也包含许可证，位置为 `Memory Glass.app/Contents/Resources/LICENSE`。

## 反馈与贡献

欢迎在 [Issues](https://github.com/xiematt125-dotcom/Bunny-Can-Bite/issues) 报告问题或提出建议。请附上 macOS 版本、芯片型号、应用版本和复现步骤；发布截图或诊断信息前，先移除私人路径和敏感程序信息。

代码贡献可通过 Pull Request 提交。请先运行 `./Tests/run-tests.sh` 和 `./build.sh`，说明改动目的和验证结果；涉及菜单栏、浮层或登录项的改动还需在真实 macOS 图形会话中验证。
