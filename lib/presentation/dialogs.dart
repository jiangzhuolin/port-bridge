import 'package:flutter/material.dart';

import '../application/bridge_controller.dart';
import '../domain/rule.dart';
import '../l10n/strings.dart';
import '../platform/desktop_integration.dart';
import 'theme.dart';

class RuleDialog extends StatefulWidget {
  const RuleDialog({super.key, required this.controller, this.rule});
  final BridgeController controller;
  final ForwardRule? rule;
  @override
  State<RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<RuleDialog> {
  late final name = TextEditingController(text: widget.rule?.name ?? '');
  late final listenHost = TextEditingController(
    text: widget.rule?.listenHost ?? '127.0.0.1',
  );
  late final listenPort = TextEditingController(
    text: '${widget.rule?.listenPort ?? 9000}',
  );
  late final targetHost = TextEditingController(
    text: widget.rule?.targetHost ?? '',
  );
  late final targetPort = TextEditingController(
    text: '${widget.rule?.targetPort ?? 8080}',
  );
  late bool autoStart = widget.rule?.autoStart ?? false;
  Object? error;
  bool saving = false;
  @override
  void dispose() {
    for (final controller in [
      name,
      listenHost,
      listenPort,
      targetHost,
      targetPort,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final local = int.tryParse(listenPort.text.trim()),
          remote = int.tryParse(targetPort.text.trim());
      if (local == null || remote == null) {
        throw const BridgeException('invalidPort');
      }
      final rule = ForwardRule(
        id: widget.rule?.id ?? ForwardRule.newId(),
        name: name.text.trim(),
        listenHost: listenHost.text.trim(),
        listenPort: local,
        targetHost: targetHost.text.trim(),
        targetPort: remote,
        autoStart: autoStart,
      ).validate();
      await widget.controller.saveRule(rule);
      if (mounted) Navigator.pop(context);
    } catch (value) {
      if (mounted) {
        setState(() {
          error = value;
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings(widget.controller.language);
    Widget field(
      String key,
      TextEditingController controller, {
      bool port = false,
      bool focus = false,
    }) => TextField(
      key: ValueKey(key),
      controller: controller,
      autofocus: focus,
      enabled: !saving,
      keyboardType: port ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: s(key)),
      onSubmitted: (_) => save(),
    );
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alt_route_rounded, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s(widget.rule == null ? 'addTitle' : 'editTitle'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: s('close'),
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  s('ruleHint'),
                  style: const TextStyle(color: muted, height: 1.5),
                ),
                const SizedBox(height: 24),
                field('ruleName', name, focus: true),
                const SizedBox(height: 24),
                _section(s('listenSection')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(flex: 3, child: field('listenHost', listenHost)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: field('listenPort', listenPort, port: true),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s('listenHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                _section(s('targetSection')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(flex: 3, child: field('targetHost', targetHost)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: field('targetPort', targetPort, port: true),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  s('targetHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: autoStart,
                  title: Text(s('autoRule')),
                  onChanged: saving
                      ? null
                      : (value) => setState(() => autoStart = value!),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      s.error(error!),
                      key: const ValueKey('ruleError'),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: Text(s('cancel')),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      key: const ValueKey('saveRule'),
                      onPressed: saving ? null : save,
                      child: Text(s('save')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String label) => Text(
    label,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: muted,
      letterSpacing: 1.2,
    ),
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.controller});
  final BridgeController controller;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  Object? error;
  bool busy = false;
  Future<void> change(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (value) {
      if (mounted) setState(() => error = value);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, s = Strings(widget.controller.language);
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s('settings'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 26),
                  Text(
                    s('language'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    key: const ValueKey('languageSelector'),
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('English')),
                      ButtonSegment(value: 'zh_CN', label: Text('简体中文')),
                    ],
                    selected: {c.language},
                    onSelectionChanged: busy
                        ? null
                        : (value) => change(() => c.setLanguage(value.first)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s('languageHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  SwitchListTile(
                    key: const ValueKey('loginStartup'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(s('loginStartup')),
                    subtitle: Text(s('loginHint')),
                    value: c.autostart,
                    onChanged: busy
                        ? null
                        : (value) => change(() => c.setAutostart(value)),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Text(
                    s('platform'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${c.desktop.runtimeLabel}\nFlutter + Dart · v$appVersion',
                    style: const TextStyle(color: muted, height: 1.7),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    s('configLocation'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    c.store.directory.path,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        s.error(error!),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: Text(s('done')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
