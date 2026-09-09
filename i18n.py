"""English source messages and Simplified Chinese translations, rendered in the UI."""

LANGUAGES = {"en": "English", "zh_CN": "简体中文"}
DEFAULT_LANGUAGE = "en"

ZH_CN = {
    "Port Bridge": "端口桥",
    "Settings": "设置",
    "Language": "语言",
    "Apply": "应用",
    "Cancel": "取消",
    "Changes apply immediately and are saved for the next launch.": "更改立即生效，并在下次启动时保留。",
    "Unable to load settings": "无法读取设置",
    "Unable to save settings": "无法保存设置",
    "Unsupported settings format": "不支持的设置格式",
    "Unsupported language": "不支持的语言",
    "Could not read settings: {error}\n\nUsing English. The original file has been preserved. Repair it and restart to save preferences.\n{path}": "无法读取设置：{error}\n\n暂时使用英语。原文件已保留；修复文件并重启后可保存偏好。\n{path}",
    "Edit forwarding rule": "编辑转发规则",
    "Add forwarding rule": "添加转发规则",
    "Listen locally, forward to a target": "本机监听，转发到目标",
    "Enter a reachable target IP or hostname without a protocol prefix.": "填写可达的目标 IP 或主机名，不要包含协议前缀。",
    "New rule": "新规则",
    "Rule name": "规则名称",
    "Listen address": "监听地址",
    "Listen port": "监听端口",
    "Target IP / hostname": "目标 IP / 主机名",
    "Target port": "目标端口",
    "Start this rule when the application opens": "软件启动时自动启用这条规则",
    "0.0.0.0 listens on all IPv4 interfaces. Use 127.0.0.1 for local access only.": "0.0.0.0 监听所有 IPv4 网卡；仅限本机访问时使用 127.0.0.1。",
    "Save rule": "保存规则",
    "Ready": "准备就绪",
    "Clients  →  Local listening port  →  Target TCP service": "客户端  →  本机监听端口  →  目标 TCP 服务",
    "＋ Add rule": "＋ 添加规则",
    "Edit": "编辑",
    "Delete": "删除",
    "Stop all": "全部停止",
    "Start all": "全部启动",
    "Listen endpoint": "监听地址",
    "Target endpoint": "转发目标",
    "Status": "状态",
    "Active": "连接",
    "Sent / received": "发送 / 接收",
    "Auto-start": "随软件启动",
    "No forwarding rules yet\nClick Add rule to configure a listening port and target address.": "还没有转发规则\n点击「添加规则」，设置监听端口和目标地址。",
    "Select a rule to start or stop": "选择一条规则以启动或停止",
    "Stop selected": "停止所选",
    "Start selected": "启动所选",
    "Activity log": "运行日志",
    "Clear": "清空",
    "Open at desktop login": "登录桌面后自动打开",
    "Runtime platform": "运行平台",
    "Unsupported operating system: {system}": "不支持的操作系统：{system}",
    "Forwarding continues while minimized; exiting stops all rules.": "最小化继续转发；退出软件停止全部转发。",
    "TCP forwarding is ready. Application protocols are handled by the target service.": "TCP 转发已就绪；应用层协议由目标服务处理。",
    "Application": "软件",
    "Yes": "是",
    "No": "否",
    "stopped": "已停止",
    "running": "运行中",
    "starting": "启动中",
    "stopping": "停止中",
    "failed": "启动失败",
    "{running} / {count} running    ·    Connections: {connections}": "{running} / {count} 条运行中    ·    {connections} 个连接",
    "{name}  ·  Connections: {total} total / Errors: {errors}": "{name}  ·  累计 {total} 次连接 / {errors} 次异常",
    "Select a rule to start or stop. Stop a running rule before editing.": "选择一条规则以启动或停止；编辑运行中的规则前请先停止。",
    "Unable to save": "无法保存",
    "Rule saved. Click Start selected to begin forwarding.": "规则已保存，点击「启动所选」开始转发。",
    "Unable to set autostart": "无法设置自动启动",
    "Unable to load configuration": "配置读取失败",
    "Could not read configuration: {error}\n\nThe original file has been preserved. Repair it and restart the application.\n{path}": "无法读取配置：{error}\n\n原文件已保留。修复配置后重新打开软件。\n{path}",
    "Port Bridge is already running": "端口桥已运行",
    "The application is already open. Find its window in the taskbar.": "软件已打开，请在任务栏中找到端口桥窗口。",
    "Invalid rule ID": "规则 ID 无效",
    "Enter a rule name": "请输入规则名称",
    "Listen address must be an IP, such as 0.0.0.0, 127.0.0.1 or ::": "监听地址必须是 IP，例如 0.0.0.0、127.0.0.1 或 ::",
    "Enter only a target IP or hostname, without a protocol, port or brackets": "目标地址请只填 IP 或主机名，不含协议、端口或方括号",
    "Ports must be integers from 1 to 65535": "端口必须是 1–65535 的整数",
    "Invalid auto-start option": "自动启动选项无效",
    "The target points to this listening port and would create a forwarding loop": "目标指向当前监听端口，会形成转发循环",
    "Unsupported configuration format": "不支持的配置格式",
    "Configuration contains duplicate rule IDs": "配置包含重复规则 ID",
    "Unable to listen on {endpoint}: {error}": "无法监听 {endpoint}：{error}",
    "Listening on {listen} → {target}": "已监听 {listen} → {target}",
    "Forwarding loop blocked: the target is the same local listening port": "目标是本机同一监听端口，已阻止转发循环",
    "Connection failed / interrupted: {error}": "连接失败 / 中断：{error}",
    "Connection to the target timed out": "连接目标超时",
    "Stopped listening and closed existing connections": "已停止监听并关闭现有连接",
    "Application paths cannot contain newlines": "程序路径不能包含换行符",
}

EN_STATES = {
    "stopped": "Stopped", "running": "Running", "starting": "Starting",
    "stopping": "Stopping", "failed": "Failed",
}


def translate(language, message, **values):
    """Translate only application messages; user data and OS errors stay intact."""
    template = ZH_CN.get(message, message) if language == "zh_CN" else EN_STATES.get(message, message)
    rendered = {key: value.render(language) if isinstance(value, LocalizedError) else value
                for key, value in values.items()}
    return template.format(**rendered)


class LocalizedError(ValueError):
    """Keep a stable source message until the UI chooses a display language."""
    def __init__(self, message, **values):
        self.message = message
        self.values = values
        super().__init__(translate(DEFAULT_LANGUAGE, message, **values))

    def render(self, language):
        return translate(language, self.message, **self.values)


def error_text(error, language):
    return error.render(language) if isinstance(error, LocalizedError) else str(error)


def error_message(error):
    """Retain translatable details without keeping exception tracebacks in log history."""
    if isinstance(error, LocalizedError):
        return LocalizedError(error.message, **{
            key: error_message(value) if isinstance(value, BaseException) else value
            for key, value in error.values.items()
        })
    return str(error)
