import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Supported AI providers
enum AiProvider {
  openRouter('OpenRouter'),
  google('Google Gemini');

  final String label;
  const AiProvider(this.label);
}

/// Lightweight model descriptor returned by [AiProviderService.fetchModels].
class AiModelInfo {
  final String id;
  final String name;

  const AiModelInfo({required this.id, required this.name});

  @override
  String toString() => name;
}

/// Singleton service that handles AI provider / model / API-key management
/// and performs the actual LLM chat-completion call.
class AiProviderService {
  AiProviderService._();
  static final AiProviderService instance = AiProviderService._();

  // ─── SharedPreferences keys ───────────────────────────────────────
  static const _kProvider = 'ai_provider';
  static const _kModel = 'ai_model';
  static const _kApiKeyOpenRouter = 'ai_api_key_openrouter';
  static const _kApiKeyGoogle = 'ai_api_key_google';

  // ─── Defaults ─────────────────────────────────────────────────────
  static const AiProvider defaultProvider = AiProvider.google;
  static const String defaultModelGoogle = 'models/gemma-4-31b-it';
  static const String defaultModelOpenRouter =
      'nvidia/nemotron-3-nano-30b-a3b:free';

  /// Hard-coded fallback key for OpenRouter (was previously in voice_order_screen)
  static const String _fallbackOpenRouterKey = '';

  // ─── Cached state ─────────────────────────────────────────────────
  AiProvider _provider = defaultProvider;
  String _model = defaultModelGoogle;
  String _apiKeyOpenRouter = '';
  String _apiKeyGoogle = '';
  bool _loaded = false;

  AiProvider get provider => _provider;
  String get model => _model;
  String get apiKeyOpenRouter =>
      _apiKeyOpenRouter.isNotEmpty ? _apiKeyOpenRouter : _fallbackOpenRouterKey;
  String get apiKeyGoogle => _apiKeyGoogle;

  /// The effective API key for the currently selected provider.
  String get activeApiKey =>
      _provider == AiProvider.google ? apiKeyGoogle : apiKeyOpenRouter;

  // ─── Load / Save ──────────────────────────────────────────────────
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    final savedProvider = prefs.getString(_kProvider);
    if (savedProvider == AiProvider.openRouter.name) {
      _provider = AiProvider.openRouter;
    } else if (savedProvider == AiProvider.google.name) {
      _provider = AiProvider.google;
    } else {
      _provider = defaultProvider;
    }

    _model =
        prefs.getString(_kModel) ??
        (_provider == AiProvider.google
            ? defaultModelGoogle
            : defaultModelOpenRouter);

    _apiKeyOpenRouter = prefs.getString(_kApiKeyOpenRouter) ?? '';
    _apiKeyGoogle = prefs.getString(_kApiKeyGoogle) ?? '';
    _loaded = true;
  }

  Future<void> save({
    required AiProvider provider,
    required String model,
    required String apiKeyOpenRouter,
    required String apiKeyGoogle,
  }) async {
    _provider = provider;
    _model = model;
    _apiKeyOpenRouter = apiKeyOpenRouter;
    _apiKeyGoogle = apiKeyGoogle;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProvider, provider.name);
    await prefs.setString(_kModel, model);
    await prefs.setString(_kApiKeyOpenRouter, apiKeyOpenRouter);
    await prefs.setString(_kApiKeyGoogle, apiKeyGoogle);
  }

  // ─── Fetch available models from provider API ─────────────────────
  /// Returns a list of models available for [provider].
  /// Falls back to a built-in preset list on error.
  Future<List<AiModelInfo>> fetchModels(AiProvider provider) async {
    try {
      if (provider == AiProvider.openRouter) {
        return await _fetchOpenRouterModels();
      } else {
        return await _fetchGoogleModels();
      }
    } catch (e) {
      debugPrint('fetchModels error ($provider): $e');
      return _presetModels(provider);
    }
  }

  Future<List<AiModelInfo>> _fetchOpenRouterModels() async {
    final key = apiKeyOpenRouter;
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }

    final response = await http
        .get(Uri.parse('https://openrouter.ai/api/v1/models'), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('OpenRouter models API returned ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    final data = body['data'] as List<dynamic>? ?? [];

    // Lọc chỉ text models, sắp theo tên
    final models = <AiModelInfo>[];
    for (final m in data) {
      final id = m['id']?.toString() ?? '';
      final name = m['name']?.toString() ?? id;
      if (id.isEmpty) continue;
      models.add(AiModelInfo(id: id, name: name));
    }
    models.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return models;
  }

  Future<List<AiModelInfo>> _fetchGoogleModels() async {
    final key = apiKeyGoogle;
    if (key.isEmpty) return _presetModels(AiProvider.google);

    final response = await http
        .get(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models?key=$key&pageSize=100',
          ),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Google models API returned ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    final data = body['models'] as List<dynamic>? ?? [];

    final models = <AiModelInfo>[];
    for (final m in data) {
      final id = m['name']?.toString() ?? '';
      final displayName = m['displayName']?.toString() ?? id;
      final supportedMethods =
          (m['supportedGenerationMethods'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      // Chỉ lấy models hỗ trợ generateContent
      if (id.isEmpty || !supportedMethods.contains('generateContent')) continue;
      models.add(AiModelInfo(id: id, name: displayName));
    }
    models.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return models;
  }

  /// Preset fallback models when the API call fails or no key is set.
  List<AiModelInfo> _presetModels(AiProvider provider) {
    if (provider == AiProvider.google) {
      return const [
        AiModelInfo(id: 'models/gemma-4-31b-it', name: 'Gemma 4 31B IT'),
        AiModelInfo(id: 'models/gemini-2.0-flash', name: 'Gemini 2.0 Flash'),
        AiModelInfo(
          id: 'models/gemini-2.0-flash-lite',
          name: 'Gemini 2.0 Flash Lite',
        ),
        AiModelInfo(id: 'models/gemini-1.5-flash', name: 'Gemini 1.5 Flash'),
      ];
    } else {
      return const [
        AiModelInfo(
          id: 'nvidia/nemotron-3-nano-30b-a3b:free',
          name: 'NVIDIA Nemotron 3 Nano (free)',
        ),
        AiModelInfo(
          id: 'google/gemma-3-27b-it:free',
          name: 'Google Gemma 3 27B IT (free)',
        ),
        AiModelInfo(
          id: 'deepseek/deepseek-chat-v3-0324:free',
          name: 'DeepSeek Chat V3 (free)',
        ),
        AiModelInfo(
          id: 'meta-llama/llama-4-maverick:free',
          name: 'Meta Llama 4 Maverick (free)',
        ),
      ];
    }
  }

  // ─── Chat completion ──────────────────────────────────────────────
  /// Send [prompt] to the active provider and return the AI response text.
  /// Throws on network / API errors.
  Future<String> sendChatCompletion(String prompt) async {
    await load(); // ensure config is loaded

    if (_provider == AiProvider.openRouter) {
      return _sendOpenRouter(prompt);
    } else {
      return _sendGoogle(prompt);
    }
  }

  Future<String> _sendOpenRouter(String prompt) async {
    final key = apiKeyOpenRouter;
    if (key.isEmpty) throw Exception('Thiếu API key OpenRouter');

    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'OpenRouter API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body);
    return json['choices'][0]['message']['content'] as String;
  }

  Future<String> _sendGoogle(String prompt) async {
    final key = apiKeyGoogle;
    if (key.isEmpty) throw Exception('Thiếu API key Google Gemini');

    final url =
        'https://generativelanguage.googleapis.com/v1beta/$_model:generateContent?key=$key';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {'responseMimeType': 'application/json'},
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Google Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body);
    debugPrint(
      '[AiProviderService] Google raw response body: ${response.body.length > 2000 ? response.body.substring(0, 2000) : response.body}',
    );
    // Google returns: candidates[0].content.parts[0].text
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Google Gemini: không có candidates trong response');
    }
    final parts = candidates[0]['content']?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw Exception('Google Gemini: không có parts trong response');
    }
    // Gemma-4 (thinking model) trả về nhiều parts: part đầu có "thought":true
    // (nội dung suy nghĩ), part sau mới là kết quả thật. Lấy part cuối không phải thought.
    String? resultText;
    for (final p in parts.reversed) {
      if (p['thought'] == true) continue;
      final t = p['text']?.toString() ?? '';
      if (t.trim().isNotEmpty) {
        resultText = t;
        break;
      }
    }
    if (resultText == null || resultText.trim().isEmpty) {
      throw Exception(
        'Google Gemini: không tìm thấy nội dung text trong parts',
      );
    }
    debugPrint(
      '[AiProviderService] Google extracted text: ${resultText.length > 2000 ? resultText.substring(0, 2000) : resultText}',
    );
    return resultText;
  }
}
