/// Welche KI die Rezepte auswertet.
enum AiProvider {
  openai,
  gemini,
  claude;

  String get label {
    switch (this) {
      case AiProvider.openai:
        return 'OpenAI';
      case AiProvider.gemini:
        return 'Gemini';
      case AiProvider.claude:
        return 'Claude';
    }
  }

  String get keyHint {
    switch (this) {
      case AiProvider.openai:
        return 'sk-...';
      case AiProvider.gemini:
        return 'AIza… oder AQ.…';
      case AiProvider.claude:
        return 'sk-ant-...';
    }
  }

  String get keyPageUrl {
    switch (this) {
      case AiProvider.openai:
        return 'https://platform.openai.com/api-keys';
      case AiProvider.gemini:
        return 'https://aistudio.google.com/apikey';
      case AiProvider.claude:
        return 'https://console.anthropic.com/settings/keys';
    }
  }

  String get storageKey {
    switch (this) {
      case AiProvider.openai:
        return 'openai_api_key';
      case AiProvider.gemini:
        return 'gemini_api_key';
      case AiProvider.claude:
        return 'claude_api_key';
    }
  }

  static AiProvider fromStorage(String? value) {
    switch (value) {
      case 'gemini':
        return AiProvider.gemini;
      case 'claude':
        return AiProvider.claude;
      default:
        return AiProvider.openai;
    }
  }

  String get storageValue {
    switch (this) {
      case AiProvider.openai:
        return 'openai';
      case AiProvider.gemini:
        return 'gemini';
      case AiProvider.claude:
        return 'claude';
    }
  }
}
