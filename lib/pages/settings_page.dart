import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings page is presentation layer only:
// it edits values through AppSettingsController.
class AppSettingsController extends ChangeNotifier {
  static const _kThemeMode = 'settings.themeMode';
  static const _kPrimaryColor = 'settings.primaryColor';
  static const _kSoundAlerts = 'settings.soundAlerts';
  static const _kDesktopPush = 'settings.desktopPush';
  static const _kFetchSeconds = 'settings.fetchSeconds';
  static const _kConfirmDismiss = 'settings.confirmDismiss';
  static const _kConfirmLogout = 'settings.confirmLogout';
  static const _kSystemHints = 'settings.systemHints';

  ThemeMode themeMode = ThemeMode.system;
  Color primaryColor = const Color(0xFF1A1A1B);
  bool soundAlerts = true;
  bool desktopPushNotifications = true;
  int fetchIntervalSeconds = 60;
  bool confirmBeforeDismiss = true;
  bool confirmBeforeLogout = true;
  bool showSystemHints = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeRaw = prefs.getString(_kThemeMode);
    if (modeRaw != null) {
      themeMode = switch (modeRaw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    }
    final colorRaw = prefs.getInt(_kPrimaryColor);
    if (colorRaw != null) primaryColor = Color(colorRaw);

    soundAlerts = prefs.getBool(_kSoundAlerts) ?? soundAlerts;
    desktopPushNotifications = prefs.getBool(_kDesktopPush) ?? desktopPushNotifications;
    fetchIntervalSeconds = prefs.getInt(_kFetchSeconds) ?? fetchIntervalSeconds;
    confirmBeforeDismiss = prefs.getBool(_kConfirmDismiss) ?? confirmBeforeDismiss;
    confirmBeforeLogout = prefs.getBool(_kConfirmLogout) ?? confirmBeforeLogout;
    showSystemHints = prefs.getBool(_kSystemHints) ?? showSystemHints;
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
  }

  void setPrimaryColor(Color color) {
    primaryColor = color;
    notifyListeners();
  }

  void setSoundAlerts(bool enabled) {
    soundAlerts = enabled;
    notifyListeners();
  }

  void setDesktopPush(bool enabled) {
    desktopPushNotifications = enabled;
    notifyListeners();
  }

  void setFetchIntervalSeconds(int seconds) {
    fetchIntervalSeconds = seconds;
    notifyListeners();
  }

  void setConfirmBeforeDismiss(bool enabled) {
    confirmBeforeDismiss = enabled;
    notifyListeners();
  }

  void setConfirmBeforeLogout(bool enabled) {
    confirmBeforeLogout = enabled;
    notifyListeners();
  }

  void setShowSystemHints(bool enabled) {
    showSystemHints = enabled;
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kThemeMode,
      switch (themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
    await prefs.setInt(_kPrimaryColor, primaryColor.toARGB32());
    await prefs.setBool(_kSoundAlerts, soundAlerts);
    await prefs.setBool(_kDesktopPush, desktopPushNotifications);
    await prefs.setInt(_kFetchSeconds, fetchIntervalSeconds);
    await prefs.setBool(_kConfirmDismiss, confirmBeforeDismiss);
    await prefs.setBool(_kConfirmLogout, confirmBeforeLogout);
    await prefs.setBool(_kSystemHints, showSystemHints);
  }
}

class SettingsPage extends StatefulWidget {
  final AppSettingsController settings;
  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _fetchChoices = [30, 60, 300];
  static const _colors = [
    Color(0xFF1A1A1B),
    Color(0xFF0D6EFD),
    Color(0xFF6F42C1),
    Color(0xFF198754),
  ];
  @override
  Widget build(BuildContext context) {
    final s = widget.settings;

    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text('Manage app behavior, hardware sync, and notifications', style: TextStyle(color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await s.save();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Settings saved')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _SectionCard(
                              title: 'App Customization',
                              child: Column(
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Theme Mode'),
                                    trailing: DropdownButton<ThemeMode>(
                                      value: s.themeMode,
                                      onChanged: (v) => s.setThemeMode(v ?? ThemeMode.system),
                                      items: const [
                                        DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                                        DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                                        DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                                      ],
                                    ),
                                  ),
                                  const Divider(),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Primary Color'),
                                    subtitle: Wrap(
                                      spacing: 8,
                                      children: _colors
                                          .map(
                                            (c) => GestureDetector(
                                              onTap: () => s.setPrimaryColor(c),
                                              child: Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  color: c,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: s.primaryColor.toARGB32() == c.toARGB32() ? Colors.black : Colors.transparent,
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _SectionCard(
                              title: 'Notification Preferences',
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    value: s.soundAlerts,
                                    onChanged: s.setSoundAlerts,
                                    title: const Text('Sound Alerts (Critical Flood)'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  const Divider(),
                                  SwitchListTile(
                                    value: s.desktopPushNotifications,
                                    onChanged: s.setDesktopPush,
                                    title: const Text('Desktop Push Notifications'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _SectionCard(
                              title: 'Hardware Sync Intervals',
                              child: Column(
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Data Fetch Interval'),
                                    subtitle: Text(_labelForSeconds(s.fetchIntervalSeconds)),
                                  ),
                                  Slider(
                                    value: _fetchChoices.indexOf(s.fetchIntervalSeconds).toDouble().clamp(0, (_fetchChoices.length - 1).toDouble()),
                                    min: 0,
                                    max: (_fetchChoices.length - 1).toDouble(),
                                    divisions: _fetchChoices.length - 1,
                                    label: _labelForSeconds(s.fetchIntervalSeconds),
                                    onChanged: (v) => s.setFetchIntervalSeconds(_fetchChoices[v.round().clamp(0, _fetchChoices.length - 1)]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _SectionCard(
                              title: 'Basic Functions',
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    value: s.confirmBeforeDismiss,
                                    onChanged: s.setConfirmBeforeDismiss,
                                    title: const Text('Confirm Before Dismiss Alert'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  const Divider(),
                                  SwitchListTile(
                                    value: s.confirmBeforeLogout,
                                    onChanged: s.setConfirmBeforeLogout,
                                    title: const Text('Confirm Before Logout'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  const Divider(),
                                  SwitchListTile(
                                    value: s.showSystemHints,
                                    onChanged: s.setShowSystemHints,
                                    title: const Text('Show System Hints'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _labelForSeconds(int seconds) {
    if (seconds < 60) return 'Every ${seconds}s';
    if (seconds == 60) return 'Every 1m';
    return 'Every ${seconds ~/ 60}m';
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

