import 'package:flutter/material.dart';

import '../application/bridge_controller.dart';
import '../domain/rule.dart';
import '../domain/appearance.dart';
import '../domain/window_preferences.dart';
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
        throw BridgeException('invalidPort');
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
        constraints: BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.alt_route_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s(widget.rule == null ? 'addTitle' : 'editTitle'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: s('close'),
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  s('ruleHint'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 24),
                field('ruleName', name, focus: true),
                SizedBox(height: 24),
                _section(context, s('listenSection')),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(flex: 3, child: field('listenHost', listenHost)),
                    SizedBox(width: 14),
                    Expanded(
                      child: field('listenPort', listenPort, port: true),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  s('listenHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: 24),
                _section(context, s('targetSection')),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(flex: 3, child: field('targetHost', targetHost)),
                    SizedBox(width: 14),
                    Expanded(
                      child: field('targetPort', targetPort, port: true),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  s('targetHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: 18),
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
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      s.error(error!),
                      key: ValueKey('ruleError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      child: Text(s('cancel')),
                    ),
                    SizedBox(width: 12),
                    FilledButton(
                      key: ValueKey('saveRule'),
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

  Widget _section(BuildContext context, String label) => Text(
    label,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          constraints: BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s('settings'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 26),
                  Text(
                    s('language'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 12),
                  SegmentedButton<String>(
                    key: ValueKey('languageSelector'),
                    segments: [
                      ButtonSegment(value: 'en', label: Text('English')),
                      ButtonSegment(value: 'zh_CN', label: Text('简体中文')),
                    ],
                    selected: {c.language},
                    onSelectionChanged: busy
                        ? null
                        : (value) => change(() => c.setLanguage(value.first)),
                  ),
                  SizedBox(height: 12),
                  Text(
                    s('languageHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Text(
                    s('appearance'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 12),
                  InputDecorator(
                    decoration: InputDecoration(labelText: s('themeMode')),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AppThemeMode>(
                        key: ValueKey('themeSelector'),
                        value: c.appearance.mode,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          for (final mode in AppThemeMode.values)
                            DropdownMenuItem(
                              value: mode,
                              child: Text(s('theme_${mode.name}')),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  change(
                                    () => c.setAppearance(
                                      Appearance(
                                        mode: value,
                                        accent: c.appearance.accent,
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    s('accentColor'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in AppAccent.values)
                        ChoiceChip(
                          key: ValueKey('accent-${color.name}'),
                          avatar: Icon(
                            Icons.circle,
                            size: 16,
                            color: accentSeed(color),
                          ),
                          label: Text(s('accent_${color.name}')),
                          selected: c.appearance.accent == color,
                          onSelected: busy
                              ? null
                              : (_) => change(
                                  () => c.setAppearance(
                                    Appearance(
                                      mode: c.appearance.mode,
                                      accent: color,
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    s('appearanceHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Text(
                    s('windowBehavior'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 8),
                  SwitchListTile(
                    key: ValueKey('minimizeToTray'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(s('minimizeToTray')),
                    subtitle: Text(s('minimizeToTrayHint')),
                    value: c.windowPreferences.minimizeToTray,
                    onChanged: busy
                        ? null
                        : (value) => change(
                            () => c.setWindowPreferences(
                              WindowPreferences(
                                minimizeToTray: value,
                                closeAction: c.windowPreferences.closeAction,
                              ),
                            ),
                          ),
                  ),
                  SizedBox(height: 16),
                  InputDecorator(
                    decoration: InputDecoration(labelText: s('closeAction')),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<CloseAction>(
                        key: ValueKey('closeActionSelector'),
                        value: c.windowPreferences.closeAction,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          for (final action in CloseAction.values)
                            DropdownMenuItem(
                              value: action,
                              child: Text(s('close_${action.name}')),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                                if (value != null) {
                                  change(
                                    () => c.setWindowPreferences(
                                      WindowPreferences(
                                        minimizeToTray:
                                            c.windowPreferences.minimizeToTray,
                                        closeAction: value,
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    s('closeActionHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (c.windowError != null)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        s.error(c.windowError!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  SwitchListTile(
                    key: ValueKey('loginStartup'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(s('loginStartup')),
                    subtitle: Text(s('loginHint')),
                    value: c.autostart,
                    onChanged: busy
                        ? null
                        : (value) => change(() => c.setAutostart(value)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  Text(
                    s('platform'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${c.desktop.runtimeLabel}\nFlutter + Dart · v$appVersion',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.7,
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    s('configLocation'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: 8),
                  SelectableText(
                    c.store.directory.path,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (error != null)
                    Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        s.error(error!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (c.requestExit != null)
                        TextButton.icon(
                          key: const ValueKey('exitApplication'),
                          onPressed: busy
                              ? null
                              : () => change(() async {
                                  await c.requestExit?.call();
                                }),
                          icon: const Icon(Icons.logout, size: 18),
                          label: Text(s('exitApp')),
                        )
                      else
                        const SizedBox.shrink(),
                      FilledButton(
                        onPressed: busy ? null : () => Navigator.pop(context),
                        child: Text(s('done')),
                      ),
                    ],
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
