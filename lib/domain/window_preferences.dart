enum CloseAction { minimize, exit }

class WindowPreferences {
  const WindowPreferences({
    this.minimizeToTray = false,
    this.closeAction = CloseAction.exit,
    this.closeActionConfirmed = false,
  });

  final bool minimizeToTray;
  final CloseAction closeAction;
  final bool closeActionConfirmed;

  factory WindowPreferences.fromSettings(Map<String, dynamic> settings) =>
      WindowPreferences(
        minimizeToTray: settings['minimize_to_tray'] == true,
        closeActionConfirmed:
            settings['close_action_confirmed'] == true &&
            ['exit', 'minimize'].contains(settings['close_action']),
        closeAction: settings['close_action'] == 'minimize'
            ? CloseAction.minimize
            : CloseAction.exit,
      );
}
