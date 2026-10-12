# Bunny Can Bite 项目指引

仓库品牌为 Bunny Can Bite；本仓库提供的 macOS 应用名称仍为 Memory Glass。

## GitHub 账号与仓库

- 用户指定的唯一同步仓库：`xiematt125-dotcom/Bunny-Can-Bite`。
- `origin` 应为 `https://github.com/xiematt125-dotcom/Bunny-Can-Bite.git`。
- 使用 `xiematt125-dotcom` 的本机 GitHub 登录推送；未来提交署名也使用该账号。旧提交历史保留原有署名。
- 仓库采用 **MIT** 许可证，并保持 **public**。发布前后均核实 GitHub 返回的可见性。用户在 2026-10-12 明确要求公开开源，此决定取代此前的私有发布要求。

## 每次应用更新的交付要求

用户已明确授权：以后每次更新 Memory Glass，都要将代码同步到上述公开仓库，并将对应版本的 **PKG 和 DMG** 安装包正式公开发布到 GitHub Releases。此授权覆盖这些更新的代码推送、版本标签、安装包上传和公开 Release 发布；正常完成这些步骤无需再次询问。

每次应用更新按以下流程交付：

1. 更新应用版本号和 build number，完成与改动相关的测试、构建和必要的真实 macOS 界面验证。
2. 从本次最终源码构建应用，使用 `package.sh` 生成对应版本的 `MemoryGlass-<版本>-arm64.pkg` 和 `.dmg`。安装包内应用必须包含当前 MIT `LICENSE`。检查包内版本、架构、安装位置及实际签名状态，验证 PKG 内容和 DMG 完整性。
3. 核实 GitHub 当前登录账号为 `xiematt125-dotcom`，仓库为 public；提交并推送最终代码，核对远程提交 SHA。公开提交前检查改动，排除凭据、私人路径和本机采样数据。
4. 使用新的 `v<版本>` 标签创建 Release，明确指向已推送的构建源码提交。发布说明写清更新内容、安装步骤、适用系统和实际签名/公证状态。
5. 先上传到草稿 Release：PKG、DMG，以及仅覆盖本次已上传安装包的 `SHA256SUMS.txt`。重新下载远程资产，校验 SHA256 和文件内容是否与本地一致。
6. 校验通过后正式发布 Release，并标记为 Latest。再次确认版本标签对应源码提交、资产完整、Release 已发布且仓库仍为 public；验证未登录访问可查看源码并下载安装包。
7. 向用户提供发布页和 PKG/DMG 下载链接，以及真实存在的安装限制。

已经发布的旧版本及资产应保留；应用更新使用新版本号，避免覆盖旧版本。单纯修改文档或项目指引时同步代码即可，无需为没有变化的应用重复构建或发布安装包。

如果登录、权限、构建、校验或上传失败，报告具体未完成环节并继续处理可独立推进的工作；不能将代码已推送或文件已上传当作完整发布成功。

## 常用验证入口

- `./Tests/run-tests.sh`：现有回归测试。
- `./build.sh <输出目录>`：构建应用。
- `./package.sh <输出目录> '<已构建应用路径>'`：生成 PKG 和 DMG。
- GitHub Releases：<https://github.com/xiematt125-dotcom/Bunny-Can-Bite/releases>。
