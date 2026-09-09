# 端口桥 · Port Bridge

[English](README.md) | 简体中文

轻量级桌面 TCP 端口转发工具。在本机地址和端口上监听，将连接转发到目标服务，并在同一窗口中管理规则、查看连接与流量。

Port Bridge 使用 Python 标准库、Tkinter 和 asyncio 构建，支持 Windows、macOS 和 Linux 桌面，无需额外的转发工具或逐条配置系统服务。源码运行不需要 pip 依赖；独立程序包内置 Python 和 Tk。

## 功能

- 添加、编辑、删除多条规则，单独或批量启动、停止。
- 查看活动和累计连接数、发送 / 接收流量、异常和运行日志。
- 本地保存规则，可选择在软件打开时自动启用。
- Windows、macOS 和 Linux 原生启动入口、桌面登录自启动及单实例保护。
- 在 **设置 → 语言** 中切换英语和简体中文，立即生效并记住选择，正在转发的连接持续运行。
- 双向转发 TCP 流量，支持 TCP 半关闭，以及 IPv4、IPv6 监听地址。

## 安装

### 系统与架构支持

| 平台 | x86_64（Intel / AMD） | ARM64（AArch64 / Apple Silicon） | 桌面集成 |
| --- | --- | --- | --- |
| Windows 10/11 | 源码及独立 `.exe` 程序包 | 源码及独立 `.exe` 程序包，需带 Tk 的 ARM64 Python | 开始菜单及启动文件夹快捷方式 |
| macOS | 源码及独立 `.app` 程序包 | 源码及独立 `.app` 程序包 | `~/Applications` 启动入口和用户 LaunchAgent |
| Ubuntu / Debian / Linux Mint | 源码、独立程序包、`.deb` | 源码、独立程序包、`.deb` | 应用菜单和 XDG 自启动 |
| Fedora、Arch / Manjaro、openSUSE | 源码及系统库兼容的独立程序包 | 发行版提供 ARM64 Python/Tk 时可运行源码，系统库兼容时可运行独立程序包 | 应用菜单和 XDG 自启动 |
| Raspberry Pi OS / 其他 32 位 ARM Linux | — | ARM64 需 64 位系统；**ARMv7 / armhf 使用源码或架构无关的 `.deb`** | 应用菜单和 XDG 自启动 |

独立程序包重点支持 **x86_64** 和 **arm64**。ARMv7 是独立的 32 位架构，不能与 ARM64 混用。源码不区分架构，但 Python、Tcl/Tk 和独立程序包必须与运行架构匹配。各发行版的架构供应范围不同，例如官方 Arch Linux 软件包面向 x86_64，ARM 衍生版使用自己的仓库。

**设置 → 运行平台** 显示操作系统（含 Linux 发行版）、Python 版本和运行架构，也可执行 `python app.py --platform-info` 查看。模拟运行的 x86_64 Python 仍会显示 x86_64，并生成 x86_64 程序包。

源码要求 Python 3.10+ 和 Tkinter；Windows ARM64 原生 Tk 支持请使用 Python 3.11+。需要图形桌面会话，Linux Tk 使用 X11（Wayland 会话可通过 XWayland），macOS 使用当前 python.org 安装器提供的原生 Aqua Tk。程序运行不依赖特定的 Linux 包管理器。

仓库提供 Windows、macOS、Ubuntu 各自 x86_64 / ARM64 的六目标 GitHub Actions 配置。本地已验证 Windows x86_64 和 Debian x86_64；macOS 与 ARM 硬件验证需由对应 CI 执行。ARMv7 及其他 Linux 发行版属于源码兼容目标，本地尚未进行对应硬件实测。

### 从源码运行

下载或克隆仓库，安装架构匹配的 Python/Tk，然后进入项目目录：

| 系统 | 安装 Python / Tkinter |
| --- | --- |
| Windows | 从 [python.org](https://www.python.org/downloads/windows/) 安装 x86_64 或 ARM64 Python，启用 Tcl/Tk |
| macOS | 使用 [python.org](https://www.python.org/downloads/macos/) 的 universal2 安装器，并使用与 CPU 匹配的原生解释器 |
| Ubuntu / Debian / Linux Mint | `sudo apt install python3 python3-tk` |
| Fedora | `sudo dnf install python3 python3-tkinter` |
| Arch / Manjaro | `sudo pacman -S python tk` |
| openSUSE | 先执行 `zypper search -s 'python3*-tk'`，安装与解释器对应的 Tk 包，例如 Python 3.13 对应 `python313-tk` |

```bash
python3 -m tkinter
python3 app.py
```

Windows 将 `python3` 换为 `python`。第一条命令打开 Tk 测试窗口，关闭后再启动 Port Bridge。Tkinter 是系统 / Python 组件，不通过 pip 安装。

### 安装到当前用户

安装 Python/Tk 后执行 `python3 install.py`（Windows 使用 `python install.py`），无需管理员权限。安装器会创建 Windows 开始菜单快捷方式、macOS 的 `~/Applications/Port Bridge.app`，或 Linux 应用菜单入口。源码安装仍依赖安装时使用的 Python；解释器移动后需要重新运行安装器。

### 独立程序包

按下方说明本地构建，或从成功的 GitHub Actions 运行中下载产物，同时匹配系统与架构：

```text
port-bridge-1.0.0-windows-x86_64.zip
port-bridge-1.0.0-windows-arm64.zip
port-bridge-1.0.0-macos-x86_64.zip
port-bridge-1.0.0-macos-arm64.zip
port-bridge-1.0.0-linux-x86_64.tar.gz
port-bridge-1.0.0-linux-arm64.tar.gz
```

完整解压后，Windows 打开 `PortBridge/PortBridge.exe`，macOS 打开 `PortBridge.app`（可移入 Applications），Linux 执行 `PortBridge/PortBridge`。保留程序包内的配套文件。在程序放到固定位置后再启用登录自启动；移动程序后，关闭并重新启用此选项。

Linux 独立程序包依赖兼容的系统库（包括 glibc）和图形桌面。CI 使用 Ubuntu 22.04 构建，不代表适配所有 Linux 版本或 musl 发行版；环境不兼容时使用源码安装，或在目标发行版构建。macOS CI 使用 macOS 15，不代表生成的包支持更早版本；需要旧系统时在对应系统上源码运行或构建。CI 产物不包含发布者数字签名或 Apple 公证。

### Debian 安装包

如果已下载或构建 Debian 安装包：

```bash
sudo apt install ./port-bridge_1.0.0_all.deb
```

安装包声明了 Python 和 Tkinter 依赖。随后从应用菜单打开 **端口桥 / Port Bridge**，或运行 `port-bridge`。`.deb` 包含纯 Python，声明 `Architecture: all`，在 amd64、arm64 或 armhf 系统上使用发行版原生的 Python/Tk，并非内置某种架构的可执行文件。建议在 Debian 安装包和用户安装之间选择一种，避免重复的启动入口；两者使用相同的配置目录。

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

**软件启动时自动启用这条规则** 控制下次打开软件时是否自动启动该规则；**全部启动** 会启动所有规则，不受此选项限制。**登录桌面后自动打开** 通过 Windows 启动文件夹、macOS LaunchAgent 或 Linux XDG 自启动，在当前用户登录图形桌面后启动软件，不会在登录前作为系统服务启动。

## 运行行为与限制

- 仅转发 TCP，不转发 UDP，不转换应用层协议，也不实现 HTTP / SOCKS 服务端。可转发到已有代理的 TCP 连接，但不支持 SOCKS5 UDP 转发。
- 不内置身份验证或加密；访问控制与传输安全取决于网络配置和目标服务。
- 最小化窗口继续转发；退出软件停止监听并关闭现有连接。无托盘模式或后台系统服务。
- 目标不可达时，当前连接失败，监听仍保持运行；目标恢复后，新客户端可重新连接。
- 每条规则最多接受 512 个并发连接，每个方向使用 64 KiB 分块和背压。连接目标超时为 10 秒；已建立的空闲连接没有活动超时。
- 发送 / 接收流量以转发器为视角，规则启动时重置统计。最近 500 条日志保存在内存中，不写入磁盘。
- 软件不会修改客户端代理设置、容器网络、防火墙或 Docker daemon 的代理配置。

## 配置文件

规则与设置按用户保存：

| 系统 | 配置目录 | 源码安装目录 | 登录自启动入口 |
| --- | --- | --- | --- |
| Windows | `%APPDATA%/port-bridge` | `%LOCALAPPDATA%/port-bridge` | `%APPDATA%/Microsoft/Windows/Start Menu/Programs/Startup/Port Bridge.lnk` |
| macOS | `~/Library/Application Support/port-bridge` | `~/Library/Application Support/port-bridge` | `~/Library/LaunchAgents/io.portbridge.plist` |
| Linux | `~/.config/port-bridge` | `~/.local/share/port-bridge` | `~/.config/autostart/io.portbridge.desktop` |

`rules.json` 保存规则和启动偏好，`settings.json` 保存语言（`en` 或 `zh_CN`），`app.lock` 用于单实例保护。继续支持显式设置 `XDG_CONFIG_HOME` 和 `XDG_DATA_HOME`；在 Windows/macOS 上，这些变量不会改变系统原生自启动目录。已有的 Windows/macOS 配置若保存在 `~/.config/port-bridge`，且原生目录尚无规则或设置文件，则继续使用原目录。

继续兼容已有的 version-1 规则文件，语言偏好单独保存。规则文件无法读取时会保留原文件并禁止修改，直到修复；设置文件无法读取时回退到英语并保留原文件，修复并重启后可保存偏好。未知语言代码会回退到英语。

## 故障排查

- **启动失败**：查看日志，检查端口占用、监听 IP 是否属于本机，以及是否有绑定端口的权限。
- **运行中但连接失败**：检查目标可达性、目标服务的监听地址和防火墙规则。
- **远程客户端超时**：确认客户端使用可达的主机地址，并且监听与防火墙允许该网络访问。
- **提示软件已运行**：从任务栏或 Dock 找到已打开的窗口。同一用户配置目录只允许一个实例。

## 开发

运行核心测试：

```bash
python3 -m unittest discover -s tests -v
```

在**目标操作系统上，使用匹配架构的 Python 解释器**构建独立程序包：

Linux 构建需要 `binutils`、libc 工具（`ldd`）和 venv 支持。在 Ubuntu / Debian 上，先通过 apt 安装 `python3-venv binutils`，再执行下方命令。使用系统 Python 时还需要匹配的共享库，例如 Python 3.13 对应 `libpython3.13`；其他发行版使用对应的构建依赖包。

```bash
python3 -m venv .venv
# Linux/macOS: source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
python -m pip install -r requirements-build.txt
python scripts/build_native.py --target-arch x86_64
# ARM64 系统和解释器使用 --target-arch arm64
python scripts/native_smoke.py
```

无显示器的 Linux 环境下，最后一条命令前加 `xvfb-run -a`。`--target-arch` 用于校验解释器架构，不会交叉编译。产物内的 `build-info.json` 记录系统、运行架构、Python、Tk、PyInstaller 和 Linux libc 信息。工作流仅在测试通过后保存构建产物，不会发布 GitHub Release。

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

截图保存在 `build/gui-tests/`。已安装 Debian 包时，可用 `xvfb-run -a python3 scripts/package_smoke.py` 验证系统启动入口。Windows 和 macOS 也可通过 `python scripts/gui_smoke.py` 运行 GUI 测试，包含在临时目录中验证原生自启动文件。设置 `PORT_BRIDGE_SKIP_CAPTURES=1` 可跳过截图与 Pillow 依赖，适用于没有屏幕录制权限的 macOS CI。

翻译集中维护在 `i18n.py`。运行状态代码与显示语言无关；新增面向用户的文案应使用翻译函数，并在两种语言中保留一致的占位符。

欢迎提交问题报告和 Pull Request。请提供操作系统、Python 版本、复现步骤和相关日志，并移除敏感数据。修改代码后运行相关测试；修改界面时检查两种语言。

## 卸载

先取消 **登录桌面后自动打开**，然后退出软件。Debian 安装可执行：

```bash
sudo apt remove port-bridge
```

用户安装可删除 `~/.local/share/port-bridge`、`~/.local/share/applications/io.portbridge.desktop` 和 `~/.local/share/icons/hicolor/scalable/apps/io.portbridge.svg`；设置 `$XDG_DATA_HOME` 时使用对应路径。配置默认保留，可从配置目录单独删除。

Windows 删除源码安装目录和开始菜单中的 `Port Bridge.lnk`。macOS 删除 `~/Applications/Port Bridge.app` 和源码安装目录。独立程序包可删除解压目录或 `.app`。规则和偏好仍保留在配置目录，需单独删除。

平台参考：[Python / Tkinter](https://docs.python.org/3/library/tkinter.html)、[Windows ARM64 Tk 支持](https://github.com/python/cpython/issues/90725)、[PyInstaller 平台要求](https://pyinstaller.org/en/stable/requirements.html)、[GitHub Runner 架构](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。
