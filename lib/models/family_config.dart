class FamilyConfig {
  FamilyConfig({
    required this.familyCode,
    required this.deviceName,
    this.supabaseUrl,
    this.supabaseAnonKey,
    this.openaiApiKey,
  });

  final String familyCode;
  final String deviceName;
  final String? supabaseUrl;
  final String? supabaseAnonKey;
  final String? openaiApiKey;

  bool get hasCloud {
    final url = supabaseUrl?.trim() ?? '';
    final key = supabaseAnonKey?.trim() ?? '';
    return url.isNotEmpty && key.isNotEmpty && familyCode.trim().isNotEmpty;
  }

  FamilyConfig copyWith({
    String? familyCode,
    String? deviceName,
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? openaiApiKey,
    bool clearSupabaseUrl = false,
    bool clearSupabaseAnonKey = false,
    bool clearOpenaiApiKey = false,
  }) {
    return FamilyConfig(
      familyCode: familyCode ?? this.familyCode,
      deviceName: deviceName ?? this.deviceName,
      supabaseUrl: clearSupabaseUrl ? null : (supabaseUrl ?? this.supabaseUrl),
      supabaseAnonKey: clearSupabaseAnonKey
          ? null
          : (supabaseAnonKey ?? this.supabaseAnonKey),
      openaiApiKey:
          clearOpenaiApiKey ? null : (openaiApiKey ?? this.openaiApiKey),
    );
  }

  Map<String, dynamic> toJson() => {
        'familyCode': familyCode,
        'deviceName': deviceName,
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
        'openaiApiKey': openaiApiKey,
      };

  factory FamilyConfig.fromJson(Map<String, dynamic> json) {
    return FamilyConfig(
      familyCode: json['familyCode'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Gerät',
      supabaseUrl: json['supabaseUrl'] as String?,
      supabaseAnonKey: json['supabaseAnonKey'] as String?,
      openaiApiKey: json['openaiApiKey'] as String?,
    );
  }
}
