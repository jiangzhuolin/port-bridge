# 端口桥 · Port Bridge 1.0.0

中文 Linux 桌面 TCP 端口转发工具。在 GUI 中添加、编辑、删除多条规则，单独或全部启停；显示实时连接数、发送 / 接收流量、连接异常和日志。无需 socat、pip 或逐条配置 systemd service。

## Ubuntu 安装

推荐使用随附安装包，在下载目录执行：

```bash
sudo apt install ./port-bridge_1.0.0_all.deb
```

安装器会安装 Python 3 和 Tk 图形库。随后从应用菜单打开「端口桥 / Port Bridge」，或运行 `port-bridge`。支持 Python 3.10+，Ubuntu 22.04+ / Debian 12+；需要 Linux 图形桌面会话。

也可以解压源码包安装到当前用户，无需 root 安装程序本身：

```bash
sudo apt install python3-tk
python3 install.py
```

或者直接运行 `python3 app.py`。不要同时使用 deb 和用户安装；两者共用规则配置。Python 代码也能在带 Tk 的 Windows 上运行，但登录自动启动功能仅用于 Linux。

## 你的使用场景

```text
Docker 容器 → Ubuntu 0.0.0.0:10808 → Windows IP:10808
```

点击「添加规则」：

| 字段 | 填写 |
| --- | --- |
| 规则名称 | Windows 代理 |
| Ubuntu 监听地址 | 0.0.0.0 |
| Ubuntu 监听端口 | 10808 |
| 目标 IP / 主机名 | Windows 的 VMnet8 IPv4 地址，例如 192.168.100.1 |
| 目标端口 | 10808 |

目标 IP 是示例，请在 Windows 执行 `ipconfig` 查找实际地址。NAT 模式通常使用 VMnet8；桥接模式使用 Ubuntu 可达的 Windows 局域网 IP。目标地址不要填写 `http://`，也不要填写端口。

保存后点击「启动所选」。可以重复添加其他规则。每次修改都会保存，运行中的规则须先停止再编辑。「随软件启动」只控制下次软件启动时是否启用；「全部启动」会启动所有规则。

Windows 的代理必须允许来自 Ubuntu 的连接（监听 VMnet8 IP 或 0.0.0.0），Windows 防火墙也必须允许 Ubuntu 访问该端口。Windows 只监听 127.0.0.1 时，需要先更改代理软件监听设置；本软件不会修改 Windows 配置。

如果 Ubuntu 使用 UFW，请按实际 Docker 网段放行监听端口，例如默认 bridge 网段确为 172.17.0.0/16 时：

```bash
sudo ufw allow from 172.17.0.0/16 to any port 10808 proto tcp
```

自定义 Docker 网络可能使用其他网段，可用 `docker network inspect 网络名` 查看。0.0.0.0 会监听所有 IPv4 网卡；如仅需特定网卡，可在 GUI 中填写其 IP。

## 容器访问

对于 Ubuntu 上的普通 Docker Engine bridge 网络，创建容器时加入：

```bash
docker run --add-host=host.docker.internal:host-gateway ...
```

容器里的代理地址为 `host.docker.internal:10808`。这里指向 Ubuntu 宿主机，而不是 Windows。也可以直接使用容器可达的 Ubuntu IP。容器内的 127.0.0.1 指向容器自身。

Compose 服务配置示例：

```yaml
services:
  your-app:
    image: your-existing-image
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

如果目标是 HTTP 或 mixed 代理，可在容器内测试：

```bash
curl --connect-timeout 10 --proxy http://host.docker.internal:10808 -I https://example.com
```

如果目标只提供 SOCKS5：

```bash
curl --connect-timeout 10 --proxy socks5h://host.docker.internal:10808 -I https://example.com
```

本软件透明转发 TCP，支持 HTTP CONNECT、SOCKS5 的 TCP 连接等；不转换协议，不转发 UDP / SOCKS5 UDP ASSOCIATE。容器内应用仍需设置自己的代理。本软件也不会自动更改 Docker daemon 的拉取代理。

## 自动启动与运行方式

- 勾选规则的「软件启动时自动启用这条规则」，软件下次打开时恢复该规则。
- 勾选主窗口底部的「登录 Linux 桌面后自动打开」，自动创建当前用户的桌面自启动项。
- 最小化窗口继续转发。退出软件会停止所有监听并关闭现有连接。
- 自启动发生在登录图形桌面后，不是在无人登录的系统引导阶段。无托盘或后台系统服务。
- 规则配置：`${XDG_CONFIG_HOME:-~/.config}/port-bridge/rules.json`。
- 自启动项：`${XDG_CONFIG_HOME:-~/.config}/autostart/io.portbridge.desktop`。
- 日志最多在窗口保留约 500 行，不写入磁盘。流量统计在启动规则时重置，发送 / 接收以 Ubuntu 转发器为视角。

## 排查

- **启动失败**：查看日志，通常是端口已被占用、监听 IP 不属于 Ubuntu，或低于 1024 的端口需要额外权限。10808 无需管理员权限。
- **运行中但连接失败**：「运行中」表示成功监听，不代表 Windows 目标可达。检查 Windows IP、代理监听地址、防火墙及日志。
- **目标暂时离线**：本次连接会关闭，监听保持运行；目标恢复后新连接自动重试，不需要重启规则。
- **容器超时**：确认容器实际使用 Ubuntu 地址、Ubuntu 防火墙已放行、Windows 允许 Ubuntu 访问。
- **重复运行**：Linux 下仅允许同一用户运行一个实例，在任务栏找到现有窗口。
- **启动配置损坏**：软件保留原文件，并禁止覆盖；修复 JSON 后重开。

每条规则最多同时处理 512 个连接；每个方向使用 64 KiB 分块和流量背压，避免一次读入完整流。目标建立连接超时为 10 秒。已有空闲连接不设活动超时，适合长连接代理。

## 卸载

先在 GUI 取消「登录 Linux 桌面后自动打开」并退出软件。deb 安装可执行：

```bash
sudo apt remove port-bridge
```

用户安装可删除 `~/.local/share/port-bridge`、`~/.local/share/applications/io.portbridge.desktop` 和 `~/.local/share/icons/hicolor/scalable/apps/io.portbridge.svg`；设置 XDG_DATA_HOME 时使用对应路径。配置默认保留，可单独删除配置目录。

## 开发与验证

在项目根目录启动软件：

```bash
python3 app.py
```

运行核心测试：

```bash
python3 -m unittest discover -s tests -v
```

覆盖多规则并发二进制传输、TCP 半关闭、端口冲突、停止后的连接回收与端口复用、目标恢复、IPv6、转发循环保护、配置读写与输入验证。

构建源码压缩包和 Debian 安装包（第二条命令需要 Linux 的 `dpkg-deb`）：

```bash
python3 scripts/build_package.py
bash scripts/build_deb.sh
```

发布文件生成在 `dist/`，中间文件生成在 `build/`，均不纳入 Git。构建脚本不依赖原聊天工作目录。

Linux GUI 集成测试需要 Tk、Xvfb、Pillow 和中文字体：

```bash
sudo apt install python3-tk xvfb xauth python3-pil fonts-noto-cjk
xvfb-run -a -s "-screen 0 1400x1000x24" python3 scripts/gui_smoke.py
```

实际窗口截图保存在 `build/gui-tests/`。已安装 deb 时，还可以用 `xvfb-run -a python3 scripts/package_smoke.py` 验证系统启动入口。

参考：[Python asyncio streams](https://docs.python.org/3/library/asyncio-stream.html)、[Freedesktop 自动启动规范](https://specifications.freedesktop.org/autostart/latest/)、[Docker host-gateway](https://docs.docker.com/reference/cli/docker/container/run/)。
