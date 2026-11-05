enum AppTheme { system, light, dark }

class AppSettings {
  const AppSettings({
    this.remindersEnabled = false,
    this.hour = 9,
    this.minute = 0,
    this.theme = AppTheme.system,
  }) : assert(hour >= 0 && hour <= 23),
       assert(minute >= 0 && minute <= 59);
  final bool remindersEnabled;
  final int hour;
  final int minute;
  final AppTheme theme;

  AppSettings copyWith({
    bool? remindersEnabled,
    int? hour,
    int? minute,
    AppTheme? theme,
  }) => AppSettings(
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    theme: theme ?? this.theme,
  );
  Map<String, dynamic> toJson() => {
    'remindersEnabled': remindersEnabled,
    'hour': hour,
    'minute': minute,
    'theme': theme.name,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    if (json['remindersEnabled'] is! bool ||
        json['hour'] is! int ||
        json['minute'] is! int ||
        (json['hour'] as int) < 0 ||
        (json['hour'] as int) > 23 ||
        (json['minute'] as int) < 0 ||
        (json['minute'] as int) > 59 ||
        !AppTheme.values.any((theme) => theme.name == json['theme'])) {
      throw const FormatException('Preferencias no válidas.');
    }
    return AppSettings(
      remindersEnabled: json['remindersEnabled'] as bool,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      theme: AppTheme.values.firstWhere((theme) => theme.name == json['theme']),
    );
  }
}
