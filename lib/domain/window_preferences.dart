enum CloseAction { minimize, exit }

class WindowPreferences {
  const WindowPreferences({
    this.minimizeToTray = false,
    this.closeAction = CloseAction.exit,
  });

  final bool minimizeToTray;
  final CloseAction closeAction;

  factory WindowPreferences.fromSettings(Map<String, dynamic> settings) =>
      WindowPreferences(
        minimizeToTray: settings['minimize_to_tray'] == true,
        closeAction: settings['close_action'] == 'minimize'
            ? CloseAction.minimize
            : CloseAction.exit,
      );
}
