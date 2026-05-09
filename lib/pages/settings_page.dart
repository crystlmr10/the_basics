import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Controller ──────────────────────────────────────────────────────────────

class AppSettingsController extends ChangeNotifier {
  static const _kThemeMode = 'settings.themeMode';
  static const _kPrimaryColor = 'settings.primaryColor';
  static const _kSoundAlerts = 'settings.soundAlerts';
  static const _kDesktopPush = 'settings.desktopPush';
  static const _kFetchSeconds = 'settings.fetchSeconds';
  static const _kConfirmDismiss = 'settings.confirmDismiss';
  static const _kConfirmLogout = 'settings.confirmLogout';
  static const _kSystemHints = 'settings.systemHints';

  // ── Defaults ──
  static const _defaultThemeMode = ThemeMode.system;
  static const _defaultPrimaryColor = Color(0xFF1A1A1B);
  static const _defaultSoundAlerts = true;
  static const _defaultDesktopPush = true;
  static const _defaultFetchSeconds = 60;
  static const _defaultConfirmDismiss = true;
  static const _defaultConfirmLogout = true;
  static const _defaultSystemHints = true;

  ThemeMode themeMode = _defaultThemeMode;
  Color primaryColor = _defaultPrimaryColor;
  bool soundAlerts = _defaultSoundAlerts;
  bool desktopPushNotifications = _defaultDesktopPush;
  int fetchIntervalSeconds = _defaultFetchSeconds;
  bool confirmBeforeDismiss = _defaultConfirmDismiss;
  bool confirmBeforeLogout = _defaultConfirmLogout;
  bool showSystemHints = _defaultSystemHints;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  // ── Load from prefs ──────────────────────────────────────────────────────

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
    desktopPushNotifications =
        prefs.getBool(_kDesktopPush) ?? desktopPushNotifications;
    fetchIntervalSeconds =
        prefs.getInt(_kFetchSeconds) ?? fetchIntervalSeconds;
    confirmBeforeDismiss =
        prefs.getBool(_kConfirmDismiss) ?? confirmBeforeDismiss;
    confirmBeforeLogout =
        prefs.getBool(_kConfirmLogout) ?? confirmBeforeLogout;
    showSystemHints = prefs.getBool(_kSystemHints) ?? showSystemHints;

    _loaded = true;
    notifyListeners();
  }

  // ── Setters ──────────────────────────────────────────────────────────────

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
  }

  void setPrimaryColor(Color color) {
    primaryColor = color;
    notifyListeners();
  }

  void setSoundAlerts(bool v) {
    soundAlerts = v;
    notifyListeners();
  }

  void setDesktopPush(bool v) {
    desktopPushNotifications = v;
    notifyListeners();
  }

  void setFetchIntervalSeconds(int v) {
    fetchIntervalSeconds = v;
    notifyListeners();
  }

  void setConfirmBeforeDismiss(bool v) {
    confirmBeforeDismiss = v;
    notifyListeners();
  }

  void setConfirmBeforeLogout(bool v) {
    confirmBeforeLogout = v;
    notifyListeners();
  }

  void setShowSystemHints(bool v) {
    showSystemHints = v;
    notifyListeners();
  }

  // ── Save ─────────────────────────────────────────────────────────────────

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

  // ── Reset to defaults ────────────────────────────────────────────────────

  Future<void> resetToDefaults() async {
    themeMode = _defaultThemeMode;
    primaryColor = _defaultPrimaryColor;
    soundAlerts = _defaultSoundAlerts;
    desktopPushNotifications = _defaultDesktopPush;
    fetchIntervalSeconds = _defaultFetchSeconds;
    confirmBeforeDismiss = _defaultConfirmDismiss;
    confirmBeforeLogout = _defaultConfirmLogout;
    showSystemHints = _defaultSystemHints;
    notifyListeners();
    await save();
  }
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  final AppSettingsController settings;
  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _fetchChoices = [30, 60, 300];

  static const _colorOptions = [
    _ColorOption(color: Color(0xFF1A1A1B), label: 'Charcoal'),
    _ColorOption(color: Color(0xFF0D6EFD), label: 'Blue'),
    _ColorOption(color: Color(0xFF6F42C1), label: 'Purple'),
    _ColorOption(color: Color(0xFF198754), label: 'Green'),
    _ColorOption(color: Color(0xFFDC3545), label: 'Red'),
    _ColorOption(color: Color(0xFFE07B39), label: 'Orange'),
  ];

  bool _saving = false;

  AppSettingsController get s => widget.settings;

  @override
  void initState() {
    super.initState();
    // Load settings if not already loaded
    if (!s.isLoaded) {
      s.load();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await s.save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Settings saved successfully'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset to Defaults',
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text(
          'All settings will be restored to their default values. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Reset',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await s.resetToDefaults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings reset to defaults'),
            backgroundColor: Colors.blueGrey.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        if (!s.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header
              Row(
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Settings',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w900)),
                      SizedBox(height: 4),
                      Text(
                        'Manage app behavior, sync, and notifications',
                        style: TextStyle(color: Colors.blueGrey),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Reset button
                  OutlinedButton.icon(
                    onPressed: _confirmReset,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey,
                      side: BorderSide(
                          color: Colors.blueGrey.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Save button
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save Changes',
                        style:
                            const TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Body
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Row 1: App Customization + Notifications
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // App Customization
                          Expanded(
                            child: _SectionCard(
                              icon: Icons.palette_outlined,
                              iconColor: Colors.purple,
                              title: 'App Customization',
                              children: [
                                // Theme mode — SegmentedButton
                                _SettingRow(
                                  icon: Icons.brightness_6_outlined,
                                  label: 'Theme Mode',
                                  description:
                                      'Controls the app\'s color scheme',
                                  control: SegmentedButton<ThemeMode>(
                                    segments: const [
                                      ButtonSegment(
                                        value: ThemeMode.light,
                                        icon: Icon(Icons.light_mode, size: 16),
                                        label: Text('Light'),
                                      ),
                                      ButtonSegment(
                                        value: ThemeMode.system,
                                        icon: Icon(Icons.devices, size: 16),
                                        label: Text('System'),
                                      ),
                                      ButtonSegment(
                                        value: ThemeMode.dark,
                                        icon: Icon(Icons.dark_mode, size: 16),
                                        label: Text('Dark'),
                                      ),
                                    ],
                                    selected: {s.themeMode},
                                    onSelectionChanged: (set) =>
                                        s.setThemeMode(set.first),
                                    style: ButtonStyle(
                                      textStyle:
                                          WidgetStateProperty.all(
                                              const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12)),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ),
                                const _SettingDivider(),

                                // Primary color
                                _SettingRow(
                                  icon: Icons.color_lens_outlined,
                                  label: 'Accent Color',
                                  description:
                                      'Used for buttons and highlights',
                                  control: Wrap(
                                    spacing: 8,
                                    children: _colorOptions.map((opt) {
                                      final isSelected =
                                          s.primaryColor.toARGB32() ==
                                              opt.color.toARGB32();
                                      return Tooltip(
                                        message: opt.label,
                                        child: GestureDetector(
                                          onTap: () =>
                                              s.setPrimaryColor(opt.color),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: opt.color,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.transparent,
                                                width: 2.5,
                                              ),
                                              boxShadow: isSelected
                                                  ? [
                                                      BoxShadow(
                                                        color: opt.color
                                                            .withValues(
                                                                alpha: 0.5),
                                                        blurRadius: 6,
                                                        spreadRadius: 1,
                                                      ),
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                                alpha: 0.3),
                                                        blurRadius: 0,
                                                        spreadRadius: 1,
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: isSelected
                                                ? const Icon(Icons.check,
                                                    color: Colors.white,
                                                    size: 14)
                                                : null,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Notifications
                          Expanded(
                            child: _SectionCard(
                              icon: Icons.notifications_outlined,
                              iconColor: Colors.orange,
                              title: 'Notification Preferences',
                              children: [
                                _SwitchRow(
                                  icon: Icons.volume_up_outlined,
                                  iconColor: Colors.redAccent,
                                  label: 'Sound Alerts',
                                  description:
                                      'Play audio on critical flood events',
                                  value: s.soundAlerts,
                                  onChanged: s.setSoundAlerts,
                                ),
                                const _SettingDivider(),
                                _SwitchRow(
                                  icon: Icons.desktop_windows_outlined,
                                  iconColor: Colors.blueAccent,
                                  label: 'Desktop Push Notifications',
                                  description:
                                      'Show OS-level push notifications',
                                  value: s.desktopPushNotifications,
                                  onChanged: s.setDesktopPush,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Row 2: Sync Interval + Basic Functions
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hardware Sync
                          Expanded(
                            child: _SectionCard(
                              icon: Icons.sync_outlined,
                              iconColor: Colors.teal,
                              title: 'Hardware Sync Interval',
                              children: [
                                const _SettingRow(
                                  icon: Icons.timer_outlined,
                                  label: 'Data Fetch Rate',
                                  description:
                                      'How often the app polls for new sensor data',
                                  control: SizedBox.shrink(),
                                ),
                                const SizedBox(height: 4),
                                // Fetch interval chips
                                Row(
                                  children: _fetchChoices.map((sec) {
                                    final isSelected =
                                        s.fetchIntervalSeconds == sec;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(
                                          _labelForSeconds(sec),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.blueGrey.shade700,
                                          ),
                                        ),
                                        selected: isSelected,
                                        onSelected: (_) =>
                                            s.setFetchIntervalSeconds(sec),
                                        selectedColor: Colors.teal,
                                        backgroundColor: Colors.blueGrey
                                            .withValues(alpha: 0.08),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        side: BorderSide(
                                          color: isSelected
                                              ? Colors.teal
                                              : Colors.blueGrey
                                                  .withValues(alpha: 0.2),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                        showCheckmark: false,
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                                // Visual indicator bar
                                _FetchIntervalBar(
                                  fetchChoices: _fetchChoices,
                                  selected: s.fetchIntervalSeconds,
                                  onChanged: s.setFetchIntervalSeconds,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Basic Functions
                          Expanded(
                            child: _SectionCard(
                              icon: Icons.tune_outlined,
                              iconColor: Colors.blueGrey,
                              title: 'Basic Functions',
                              children: [
                                _SwitchRow(
                                  icon: Icons.delete_sweep_outlined,
                                  iconColor: Colors.orange,
                                  label: 'Confirm Before Dismiss',
                                  description:
                                      'Show confirmation before dismissing an alert',
                                  value: s.confirmBeforeDismiss,
                                  onChanged: s.setConfirmBeforeDismiss,
                                ),
                                const _SettingDivider(),
                                _SwitchRow(
                                  icon: Icons.logout,
                                  iconColor: Colors.redAccent,
                                  label: 'Confirm Before Logout',
                                  description:
                                      'Show confirmation dialog on logout',
                                  value: s.confirmBeforeLogout,
                                  onChanged: s.setConfirmBeforeLogout,
                                ),
                                const _SettingDivider(),
                                _SwitchRow(
                                  icon: Icons.tips_and_updates_outlined,
                                  iconColor: Colors.amber.shade700,
                                  label: 'Show System Hints',
                                  description:
                                      'Display contextual help tips in the UI',
                                  value: s.showSystemHints,
                                  onChanged: s.setShowSystemHints,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Active settings summary
                      _ActiveSummaryCard(settings: s),
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
    if (seconds < 60) return '${seconds}s';
    if (seconds == 60) return '1 min';
    return '${seconds ~/ 60} min';
  }
}

// ─── Active Summary ───────────────────────────────────────────────────────────

class _ActiveSummaryCard extends StatelessWidget {
  final AppSettingsController settings;
  const _ActiveSummaryCard({required this.settings});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 16, color: Colors.blueGrey),
              const SizedBox(width: 6),
              Text(
                'Current Configuration Summary',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryChip(
                icon: Icons.brightness_6_outlined,
                label: switch (s.themeMode) {
                  ThemeMode.light => 'Light Theme',
                  ThemeMode.dark => 'Dark Theme',
                  ThemeMode.system => 'System Theme',
                },
              ),
              _SummaryChip(
                icon: Icons.timer_outlined,
                label:
                    'Fetch: ${s.fetchIntervalSeconds < 60 ? '${s.fetchIntervalSeconds}s' : '${s.fetchIntervalSeconds ~/ 60}m'}',
              ),
              if (s.soundAlerts)
                const _SummaryChip(
                    icon: Icons.volume_up_outlined, label: 'Sound On'),
              if (s.desktopPushNotifications)
                const _SummaryChip(
                    icon: Icons.notifications_active_outlined,
                    label: 'Push On'),
              if (s.confirmBeforeDismiss)
                const _SummaryChip(
                    icon: Icons.check_circle_outline,
                    label: 'Confirm Dismiss'),
              if (s.confirmBeforeLogout)
                const _SummaryChip(
                    icon: Icons.logout, label: 'Confirm Logout'),
              if (s.showSystemHints)
                const _SummaryChip(
                    icon: Icons.tips_and_updates_outlined, label: 'Hints On'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SummaryChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}

// ─── Fetch Interval Bar ───────────────────────────────────────────────────────

class _FetchIntervalBar extends StatelessWidget {
  final List<int> fetchChoices;
  final int selected;
  final ValueChanged<int> onChanged;

  const _FetchIntervalBar({
    required this.fetchChoices,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final idx = fetchChoices.indexOf(selected);
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.teal,
            inactiveTrackColor: Colors.teal.withValues(alpha: 0.15),
            thumbColor: Colors.teal,
            overlayColor: Colors.teal.withValues(alpha: 0.12),
            trackHeight: 3,
          ),
          child: Slider(
            value: idx.toDouble().clamp(
                0, (fetchChoices.length - 1).toDouble()),
            min: 0,
            max: (fetchChoices.length - 1).toDouble(),
            divisions: fetchChoices.length - 1,
            onChanged: (v) =>
                onChanged(fetchChoices[v.round().clamp(0, fetchChoices.length - 1)]),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: fetchChoices
              .map((s) => Text(
                    s < 60 ? '${s}s' : '${s ~/ 60}m',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.blueGrey.shade400),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ─── Setting Row ──────────────────────────────────────────────────────────────

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Widget control;

  const _SettingRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: Colors.blueGrey.shade500),
              const SizedBox(width: 7),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 2),
          Text(description,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.blueGrey.shade400,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          control,
        ],
      ),
    );
  }
}

// ─── Switch Row ───────────────────────────────────────────────────────────────

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: (value ? iconColor : Colors.blueGrey)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: 15, color: value ? iconColor : Colors.blueGrey),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                Text(description,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey.shade400,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: iconColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

// ─── Setting Divider ──────────────────────────────────────────────────────────

class _SettingDivider extends StatelessWidget {
  const _SettingDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
        height: 16,
        thickness: 1,
        color: Colors.black.withValues(alpha: 0.05));
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _ColorOption {
  final Color color;
  final String label;
  const _ColorOption({required this.color, required this.label});
}
