import 'dart:async';
import 'dart:ui' show AppExitResponse, FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../application/bridge_controller.dart';
import '../domain/rule.dart';
import '../domain/appearance.dart';
import '../l10n/strings.dart';
import '../platform/desktop_integration.dart';
import 'dialogs.dart';
import 'theme.dart';

class BridgeApp extends StatefulWidget {
  const BridgeApp({
    super.key,
    required this.controller,
    this.onShutdown,
    this.onExitRequested,
  });
  final BridgeController controller;
  final Future<void> Function()? onShutdown;
  final Future<AppExitResponse> Function()? onExitRequested;
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
        if (widget.onExitRequested != null) return widget.onExitRequested!();
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
      theme: bridgeTheme(accent: widget.controller.appearance.accent),
      darkTheme: bridgeTheme(
        brightness: Brightness.dark,
        accent: widget.controller.appearance.accent,
      ),
      themeMode: switch (widget.controller.appearance.mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      locale: widget.controller.language == 'zh_CN'
          ? Locale('zh', 'CN')
          : Locale('en'),
      supportedLocales: [Locale('en'), Locale('zh', 'CN')],
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
                              SizedBox(height: 8),
                              Text(
                                s('subtitle'),
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!wide)
                          IconButton(
                            key: ValueKey('settingsButton'),
                            tooltip: s('settings'),
                            onPressed: () => settings(context),
                            icon: Icon(Icons.settings_outlined),
                          ),
                      ],
                    ),
                    SizedBox(height: 28),
                    _metrics(context),
                    SizedBox(height: 28),
                    if (controller.configError != null)
                      _warning(
                        context,
                        s('configProtected'),
                        controller.configError!,
                      ),
                    if (controller.settingsError != null)
                      _warning(
                        context,
                        s('settingsProtected'),
                        controller.settingsError!,
                      ),
                    if (controller.engineFailed)
                      _warning(context, s('engineStopped'), ''),
                    Expanded(flex: 3, child: _rulePanel(context)),
                    SizedBox(height: 20),
                    Expanded(flex: 2, child: _logPanel(context)),
                    SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(width: 8),
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
    color: Theme.of(context).colorScheme.surface,
    child: Container(
      width: 222,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.alt_route_rounded,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s('appName'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            Text(s('tagline'), style: Theme.of(context).textTheme.bodySmall),
            SizedBox(height: 48),
            Text(
              s('workspace'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(
                  Icons.account_tree_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                title: Text(
                  s('rules'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 8),
            ListTile(
              key: ValueKey('settingsButton'),
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
              leading: Icon(
                Icons.tune_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
              title: Text(
                s('settings'),
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => settings(context),
            ),
            Spacer(),
            Divider(),
            SizedBox(height: 16),
            Text(
              s('desktopApp'),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 1.4,
              ),
            ),
            SizedBox(height: 8),
            Text(
              controller.desktop.runtimeLabel,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'v$appVersion',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
          if (i > 0) SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        items[i].$3,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          items[i].$1,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                  FittedBox(
                    child: Text(
                      items[i].$2,
                      style: TextStyle(
                        fontSize: 26,
                        color: Theme.of(context).colorScheme.onSurface,
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
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(18),
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
                    key: ValueKey('addRule'),
                    onPressed:
                        controller.configError != null || controller.saving
                        ? null
                        : () => ruleDialog(context),
                    icon: Icon(Icons.add, size: 18),
                    label: Text(s('addRule')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(height: 1),
        Expanded(
          child: controller.rules.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_link_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 46,
                          ),
                          SizedBox(height: 12),
                          Text(
                            s('emptyTitle'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 450),
                            child: Text(
                              s('emptyBody'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                height: 1.5,
                              ),
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
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
            headingTextStyle: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  ? Theme.of(context).colorScheme.primary
                  : state == 'failed'
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant;
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
                        style: TextStyle(
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
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          '→ ${rule.targetEndpoint}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: EdgeInsets.symmetric(
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      color: rule.autoStart
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
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
                            color: Theme.of(context).colorScheme.primary,
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
    context,
    Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 12, 10),
          child: Row(
            children: [
              Icon(
                Icons.terminal_rounded,
                size: 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: 10),
              Text(s('logs'), style: Theme.of(context).textTheme.titleMedium),
              Spacer(),
              TextButton(
                onPressed: controller.clearLogs,
                child: Text(s('clear')),
              ),
            ],
          ),
        ),
        Divider(height: 1),
        Expanded(
          child: controller.logs.isEmpty
              ? Center(
                  child: Text(
                    s('noLogs'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: controller.logs.length,
                  itemBuilder: (context, index) {
                    final log =
                        controller.logs[controller.logs.length - 1 - index];
                    final time =
                        '${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}';
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            time,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          SizedBox(width: 18),
                          Expanded(
                            child: Text(
                              '[${log.name ?? s('application')}]  ${s(log.code)}${log.detail.isEmpty ? '' : '  ${log.detail}'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
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

  Widget _panel(BuildContext context, Widget child) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
  Widget _warning(BuildContext context, String title, Object error) => Padding(
    padding: EdgeInsets.only(bottom: 14),
    child: Text(
      '$title${error.toString().isEmpty ? '' : '\n$error'}',
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 12,
      ),
    ),
  );
}
