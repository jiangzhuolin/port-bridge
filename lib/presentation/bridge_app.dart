import 'dart:async';
import 'dart:ui' show AppExitResponse, FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../application/bridge_controller.dart';
import '../domain/rule.dart';
import '../l10n/strings.dart';
import '../platform/desktop_integration.dart';
import 'dialogs.dart';
import 'theme.dart';

class BridgeApp extends StatefulWidget {
  const BridgeApp({super.key, required this.controller, this.onShutdown});
  final BridgeController controller;
  final Future<void> Function()? onShutdown;
  @override
  State<BridgeApp> createState() => _BridgeAppState();
}

class _BridgeAppState extends State<BridgeApp> {
  late final AppLifecycleListener lifecycle;
  @override
  void initState() {
    super.initState();
    lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.controller.shutdown();
        await widget.onShutdown?.call();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Port Bridge',
      theme: bridgeTheme(),
      locale: widget.controller.language == 'zh_CN'
          ? const Locale('zh', 'CN')
          : const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: BridgeHome(controller: widget.controller),
    ),
  );
}

class BridgeHome extends StatelessWidget {
  const BridgeHome({super.key, required this.controller});
  final BridgeController controller;
  Strings get s => Strings(controller.language);
  Future<void> action(BuildContext context, Future<void> Function() run) async {
    try {
      await run();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.error(error))));
      }
    }
  }

  void ruleDialog(BuildContext context, [ForwardRule? rule]) => unawaited(
    showDialog<void>(
      context: context,
      builder: (_) => RuleDialog(controller: controller, rule: rule),
    ),
  );
  void settings(BuildContext context) => unawaited(
    showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(controller: controller),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 1050;
        return Row(
          children: [
            if (wide) _sidebar(context),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(wide ? 32 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s('overview'),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                s('subtitle'),
                                style: const TextStyle(
                                  color: muted,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!wide)
                          IconButton(
                            key: const ValueKey('settingsButton'),
                            tooltip: s('settings'),
                            onPressed: () => settings(context),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _metrics(context),
                    const SizedBox(height: 28),
                    if (controller.configError != null)
                      _warning(s('configProtected'), controller.configError!),
                    if (controller.settingsError != null)
                      _warning(
                        s('settingsProtected'),
                        controller.settingsError!,
                      ),
                    if (controller.engineFailed)
                      _warning(s('engineStopped'), ''),
                    Expanded(flex: 3, child: _rulePanel(context)),
                    const SizedBox(height: 20),
                    Expanded(flex: 2, child: _logPanel(context)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s('footer'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _sidebar(BuildContext context) => Material(
    color: Colors.white,
    child: Container(
      width: 222,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.alt_route_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s('appName'),
                    style: const TextStyle(
                      color: ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(s('tagline'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 48),
            Text(
              s('workspace'),
              style: const TextStyle(
                color: muted,
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE9F5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(
                  Icons.account_tree_outlined,
                  color: accent,
                  size: 20,
                ),
                title: Text(
                  s('rules'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const ValueKey('settingsButton'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.tune_rounded, color: muted, size: 20),
              title: Text(
                s('settings'),
                style: const TextStyle(fontSize: 13, color: muted),
              ),
              onTap: () => settings(context),
            ),
            const Spacer(),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              s('desktopApp'),
              style: const TextStyle(
                fontSize: 10,
                color: muted,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              controller.desktop.runtimeLabel,
              style: const TextStyle(fontSize: 12, color: ink),
            ),
            const SizedBox(height: 6),
            const Text(
              'v$appVersion',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _metrics(BuildContext context) {
    final items = [
      (
        s('activeRules'),
        '${controller.running} / ${controller.rules.length}',
        Icons.alt_route_rounded,
      ),
      (
        s('connections'),
        '${controller.total('connections')}',
        Icons.hub_outlined,
      ),
      (s('sent'), humanBytes(controller.total('up')), Icons.north_east_rounded),
      (
        s('received'),
        humanBytes(controller.total('down')),
        Icons.south_west_rounded,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(items[i].$3, color: accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          items[i].$1,
                          style: const TextStyle(
                            fontSize: 10,
                            color: muted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FittedBox(
                    child: Text(
                      items[i].$2,
                      style: const TextStyle(
                        fontSize: 26,
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _rulePanel(BuildContext context) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 10,
            children: [
              Text(
                '${s('rules')}  (${controller.rules.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed:
                        controller.rules.isEmpty || controller.engineFailed
                        ? null
                        : () => action(context, controller.stopAll),
                    child: Text(s('stopAll')),
                  ),
                  OutlinedButton(
                    onPressed:
                        controller.rules.isEmpty ||
                            controller.configError != null ||
                            controller.engineFailed
                        ? null
                        : () => action(context, controller.startAll),
                    child: Text(s('startAll')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('addRule'),
                    onPressed:
                        controller.configError != null || controller.saving
                        ? null
                        : () => ruleDialog(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s('addRule')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: controller.rules.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add_link_rounded,
                            color: accent,
                            size: 46,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            s('emptyTitle'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 450),
                            child: Text(
                              s('emptyBody'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: muted, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : _table(context),
        ),
        if (controller.selected != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFF8FAFB),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              '${controller.selected!.name}  ·  ${s('totalConnections')}: ${controller.metrics[controller.selectedId]?['total'] ?? 0}  /  ${s('errors')}: ${controller.metrics[controller.selectedId]?['errors'] ?? 0}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
  );

  Widget _table(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: constraints.maxWidth < 890 ? 890 : constraints.maxWidth,
        child: SingleChildScrollView(
          child: DataTable(
            showCheckboxColumn: false,
            columnSpacing: 18,
            horizontalMargin: 20,
            headingRowHeight: 44,
            dataRowMinHeight: 70,
            dataRowMaxHeight: 76,
            headingTextStyle: const TextStyle(
              fontSize: 10,
              color: muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            columns: [
              for (final key in [
                'ruleName',
                'route',
                'status',
                'traffic',
                'autoStart',
                'actions',
              ])
                DataColumn(label: Text(s(key))),
            ],
            rows: controller.rules.map((rule) {
              final state = controller.state(rule.id),
                  metric = controller.metrics[rule.id] ?? {};
              final busy = controller.busy(rule.id);
              final color = state == 'running'
                  ? accent
                  : state == 'failed'
                  ? Colors.red
                  : muted;
              return DataRow(
                selected: controller.selectedId == rule.id,
                onSelectChanged: (_) => controller.select(rule.id),
                cells: [
                  DataCell(
                    SizedBox(
                      width: 125,
                      child: Text(
                        rule.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.listenEndpoint,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '→ ${rule.targetEndpoint}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s(state),
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${humanBytes(metric['up'] as int? ?? 0)}\n${humanBytes(metric['down'] as int? ?? 0)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.7,
                      ),
                    ),
                  ),
                  DataCell(
                    Icon(
                      rule.autoStart
                          ? Icons.check_circle_outline
                          : Icons.remove,
                      size: 18,
                      color: rule.autoStart ? accent : muted,
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: ValueKey('toggle-${rule.id}'),
                          tooltip: s(busy ? 'stop' : 'start'),
                          onPressed:
                              controller.engineFailed ||
                                  controller.configError != null ||
                                  ['starting', 'stopping'].contains(state)
                              ? null
                              : () => action(
                                  context,
                                  () => busy
                                      ? controller.stop(rule)
                                      : controller.start(rule),
                                ),
                          icon: Icon(
                            busy
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline,
                            color: accent,
                            size: 22,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: s('actions'),
                          enabled:
                              !busy &&
                              !controller.saving &&
                              controller.configError == null,
                          onSelected: (value) {
                            if (value == 'edit') {
                              ruleDialog(context, rule);
                            } else {
                              action(
                                context,
                                () => controller.deleteRule(rule),
                              );
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(s('edit')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(s('delete')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    ),
  );

  Widget _logPanel(BuildContext context) => _panel(
    Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
          child: Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 19, color: muted),
              const SizedBox(width: 10),
              Text(s('logs'), style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: controller.clearLogs,
                child: Text(s('clear')),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: controller.logs.isEmpty
              ? Center(
                  child: Text(
                    s('noLogs'),
                    style: const TextStyle(color: muted),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  itemCount: controller.logs.length,
                  itemBuilder: (context, index) {
                    final log =
                        controller.logs[controller.logs.length - 1 - index];
                    final time =
                        '${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            time,
                            style: const TextStyle(
                              color: muted,
                              fontSize: 11,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Text(
                              '[${log.name ?? s('application')}]  ${s(log.code)}${log.detail.isEmpty ? '' : '  ${log.detail}'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: ink,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _panel(Widget child) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
  Widget _warning(String title, Object error) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      '$title${error.toString().isEmpty ? '' : '\n$error'}',
      style: const TextStyle(color: Colors.red, fontSize: 12),
    ),
  );
}
