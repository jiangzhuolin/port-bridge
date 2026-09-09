# 端口桥 · Port Bridge

[English](README.md) | 简体中文

轻量级桌面 TCP 端口转发工具。在本机地址和端口上监听，将连接转发到目标服务，并在同一窗口中管理规则、查看连接与流量。

Port Bridge 使用 Python 标准库、Tkinter 和 asyncio 构建，面向 Linux 桌面，无需 pip 依赖、额外的转发工具或逐条配置系统服务。

## 功能

- 添加、编辑、删除多条规则，单独或批量启动、停止。
- 查看活动和累计连接数、发送 / 接收流量、异常和运行日志。
- 本地保存规则，可选择在软件打开时自动启用。
- 可选择在登录 Linux 桌面后启动软件。
- 在 **设置 → 语言** 中切换英语和简体中文，立即生效并记住选择，正在转发的连接持续运行。
- 双向转发 TCP 流量，支持 TCP 半关闭，以及 IPv4、IPv6 监听地址。

## 安装

需要 Python 3.10+ 和 Tkinter。Linux 安装包面向带图形桌面会话的 Ubuntu 22.04+ 和 Debian 12+。程序也可在安装了 Tkinter 的 Windows 上运行；安装器、桌面登录自启动和单实例锁仅用于 Linux。

### 从源码运行

下载或克隆仓库，进入项目目录。在 Ubuntu / Debian 上执行：

```bash
sudo apt install python3-tk
python3 app.py
```

Windows 上可使用带 Tkinter 的 Python 执行 `python app.py`。

### 安装到当前 Linux 用户

安装 Tkinter 后，在源码目录执行：

```bash
python3 install.py
```

随后从应用菜单打开 **端口桥 / Port Bridge**。安装器会将程序复制到当前用户的数据目录，本身不需要 root 权限。

### Debian 安装包

如果已下载或构建 Debian 安装包：

```bash
sudo apt install ./port-bridge_1.0.0_all.deb
```

安装包声明了 Python 和 Tkinter 依赖。随后从应用菜单打开 **端口桥 / Port Bridge**，或运行 `port-bridge`。建议在 Debian 安装包和用户安装之间选择一种，避免重复的启动入口；两者使用相同的配置目录。

## 使用方法

```text
TCP 客户端 → 运行 Port Bridge 的主机:监听端口 → 目标主机:目标端口
```

1. 点击 **添加规则**，填写规则名称、监听地址和端口、目标地址和端口。
2. 点击 **保存规则**，选中规则并点击 **启动所选**。
3. 让客户端连接监听地址和端口，在列表和日志中观察流量与异常。
4. 编辑规则前先停止它。使用 **全部启动** 或 **全部停止** 批量控制规则。

例如，通过本机 `9000` 端口访问另一台机器上监听 `8080` 端口的服务：

| 字段 | 示例 |
| --- | --- |
| 规则名称 | 开发服务 |
| 监听地址 | `127.0.0.1` |
| 监听端口 | `9000` |
| 目标 IP / 主机名 | `192.0.2.10` |
| 目标端口 | `8080` |

`192.0.2.10` 为文档示例地址，请替换为运行 Port Bridge 的机器能够访问的实际服务地址。目标主机字段不要包含 URL 协议前缀、端口或 IPv6 方括号。客户端发起连接后，Port Bridge 才连接目标，因此 **运行中** 表示监听已就绪，并不代表已检查目标可达性。

仅供本机客户端访问时使用 `127.0.0.1`。需要接受其他机器、虚拟机或容器的连接时，使用合适的主机网卡地址，或用 `0.0.0.0` 监听所有 IPv4 网卡，并配置防火墙，仅允许预期客户端访问。客户端应使用运行 Port Bridge 的主机的可达地址；`0.0.0.0` 用作监听地址。IPv6 监听可使用 `::` 或具体的 IPv6 网卡地址。

常见用途包括转发到开发服务器、通过不同的本机端口访问可达的 TCP 服务，以及让容器或虚拟机经宿主机连接服务。网络路由、目标访问权限和防火墙配置需要允许这些连接。

## 语言与偏好设置

软件默认使用英语。打开 **Settings → Language（设置 → 语言）**，选择 **English** 或 **简体中文**，点击 **Apply（应用）**。界面标签、状态、输入验证提示和软件日志立即更新。规则名称和地址保持用户输入的内容；操作系统错误详情使用系统提供的语言。

**软件启动时自动启用这条规则** 控制下次打开软件时是否自动启动该规则；**全部启动** 会启动所有规则，不受此选项限制。**登录 Linux 桌面后自动打开** 会在当前用户登录图形桌面后启动软件。

## 运行行为与限制

- 仅转发 TCP，不转发 UDP，不转换应用层协议，也不实现 HTTP / SOCKS 服务端。可转发到已有代理的 TCP 连接，但不支持 SOCKS5 UDP 转发。
- 不内置身份验证或加密；访问控制与传输安全取决于网络配置和目标服务。
- 最小化窗口继续转发；退出软件停止监听并关闭现有连接。无托盘模式或后台系统服务。
- 目标不可达时，当前连接失败，监听仍保持运行；目标恢复后，新客户端可重新连接。
- 每条规则最多接受 512 个并发连接，每个方向使用 64 KiB 分块和背压。连接目标超时为 10 秒；已建立的空闲连接没有活动超时。
- 发送 / 接收流量以转发器为视角，规则启动时重置统计。最近 500 条日志保存在内存中，不写入磁盘。
- 软件不会修改客户端代理设置、容器网络、防火墙或 Docker daemon 的代理配置。

## 配置文件

配置根目录为 `$XDG_CONFIG_HOME`；未设置该变量时使用 `~/.config`：

| 文件 | 用途 |
| --- | --- |
| `port-bridge/rules.json` | 转发规则和每条规则的启动偏好 |
| `port-bridge/settings.json` | 界面语言（`en` 或 `zh_CN`） |
| `autostart/io.portbridge.desktop` | 可选的 Linux 桌面登录自启动入口 |

继续兼容已有的 version-1 规则文件，语言偏好单独保存。规则文件无法读取时会保留原文件并禁止修改，直到修复；设置文件无法读取时回退到英语并保留原文件，修复并重启后可保存偏好。未知语言代码会回退到英语。

## 故障排查

- **启动失败**：查看日志，检查端口占用、监听 IP 是否属于本机，以及是否有绑定端口的权限。
- **运行中但连接失败**：检查目标可达性、目标服务的监听地址和防火墙规则。
- **远程客户端超时**：确认客户端使用可达的主机地址，并且监听与防火墙允许该网络访问。
- **Linux 提示软件已运行**：从任务栏找到已打开的窗口。同一用户配置目录只允许一个实例。

## 开发

运行核心测试：

```bash
python3 -m unittest discover -s tests -v
```

构建源码压缩包和 Debian 安装包（第二条命令需要 Linux 和 `dpkg-deb`）：

```bash
python3 scripts/build_package.py
bash scripts/build_deb.sh
```

发布文件输出到 `dist/`，中间文件输出到 `build/`，均不纳入 Git。安装包包含两种语言的 README 和语言资源。

在 Ubuntu / Debian 上运行 GUI 集成测试并截图：

```bash
sudo apt install python3-tk xvfb xauth python3-pil fonts-noto-cjk
xvfb-run -a -s "-screen 0 1400x1000x24" python3 scripts/gui_smoke.py
```

截图保存在 `build/gui-tests/`。已安装 Debian 包时，可用 `xvfb-run -a python3 scripts/package_smoke.py` 验证系统启动入口。Windows 安装 Pillow 后也可通过 `python scripts/gui_smoke.py` 运行 GUI 测试，届时跳过 Linux 自启动检查。

翻译集中维护在 `i18n.py`。运行状态代码与显示语言无关；新增面向用户的文案应使用翻译函数，并在两种语言中保留一致的占位符。

欢迎提交问题报告和 Pull Request。请提供操作系统、Python 版本、复现步骤和相关日志，并移除敏感数据。修改代码后运行相关测试；修改界面时检查两种语言。

## 卸载

先取消 **登录 Linux 桌面后自动打开**，然后退出软件。Debian 安装可执行：

```bash
sudo apt remove port-bridge
```

用户安装可删除 `~/.local/share/port-bridge`、`~/.local/share/applications/io.portbridge.desktop` 和 `~/.local/share/icons/hicolor/scalable/apps/io.portbridge.svg`；设置 `$XDG_DATA_HOME` 时使用对应路径。配置默认保留，可从配置目录单独删除。
