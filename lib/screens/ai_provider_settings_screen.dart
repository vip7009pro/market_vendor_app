import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_provider_service.dart';

class AiProviderSettingsScreen extends StatefulWidget {
  const AiProviderSettingsScreen({super.key});

  @override
  State<AiProviderSettingsScreen> createState() =>
      _AiProviderSettingsScreenState();
}

class _AiProviderSettingsScreenState extends State<AiProviderSettingsScreen> {
  final _service = AiProviderService.instance;

  late AiProvider _selectedProvider;
  late String _selectedModel;
  late TextEditingController _openRouterKeyCtrl;
  late TextEditingController _googleKeyCtrl;
  late TextEditingController _customModelCtrl;

  bool _loading = true;
  bool _saving = false;
  bool _fetchingModels = false;
  List<AiModelInfo> _models = [];
  bool _useCustomModel = false;

  bool _showOpenRouterKey = false;
  bool _showGoogleKey = false;

  @override
  void initState() {
    super.initState();
    _openRouterKeyCtrl = TextEditingController();
    _googleKeyCtrl = TextEditingController();
    _customModelCtrl = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    await _service.load();
    _selectedProvider = _service.provider;
    _selectedModel = _service.model;

    // Read the raw user key (not the fallback) from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    _openRouterKeyCtrl.text = prefs.getString('ai_api_key_openrouter') ?? '';
    _googleKeyCtrl.text = _service.apiKeyGoogle;
    _customModelCtrl.text = _selectedModel;

    setState(() => _loading = false);
    _fetchModelList();
  }

  Future<void> _fetchModelList() async {
    setState(() => _fetchingModels = true);
    try {
      final models = await _service.fetchModels(_selectedProvider);
      if (!mounted) return;
      setState(() {
        _models = models;
        // Check if current model is in the list
        final inList = models.any((m) => m.id == _selectedModel);
        _useCustomModel = !inList && _selectedModel.isNotEmpty;
        _fetchingModels = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _models = [];
        _useCustomModel = true;
        _fetchingModels = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    final model =
        _useCustomModel ? _customModelCtrl.text.trim() : _selectedModel;
    await _service.save(
      provider: _selectedProvider,
      model: model,
      apiKeyOpenRouter: _openRouterKeyCtrl.text.trim(),
      apiKeyGoogle: _googleKeyCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu cài đặt AI Provider')),
    );
  }

  @override
  void dispose() {
    _openRouterKeyCtrl.dispose();
    _googleKeyCtrl.dispose();
    _customModelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chọn AI Provider')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn AI Provider'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: 'Lưu',
                  onPressed: _saveConfig,
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Provider Selector ─────────────────────────────────
          Text('Nhà cung cấp AI',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<AiProvider>(
            segments: AiProvider.values
                .map((p) => ButtonSegment(value: p, label: Text(p.label)))
                .toList(),
            selected: {_selectedProvider},
            onSelectionChanged: (set) {
              final next = set.first;
              setState(() {
                _selectedProvider = next;
                // Switch to default model of the new provider
                _selectedModel = next == AiProvider.google
                    ? AiProviderService.defaultModelGoogle
                    : AiProviderService.defaultModelOpenRouter;
                _customModelCtrl.text = _selectedModel;
                _useCustomModel = false;
              });
              _fetchModelList();
            },
          ),

          const SizedBox(height: 24),

          // ─── API Key ───────────────────────────────────────────
          Text('API Key',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // Google Key
          TextField(
            controller: _googleKeyCtrl,
            obscureText: !_showGoogleKey,
            decoration: InputDecoration(
              labelText: 'Google Gemini API Key',
              hintText: 'Nhập key từ ai.google.dev',
              prefixIcon: const Icon(Icons.key),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _showGoogleKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _showGoogleKey = !_showGoogleKey),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // OpenRouter Key
          TextField(
            controller: _openRouterKeyCtrl,
            obscureText: !_showOpenRouterKey,
            decoration: InputDecoration(
              labelText: 'OpenRouter API Key',
              hintText: 'Để trống = dùng key mặc định',
              prefixIcon: const Icon(Icons.key),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showOpenRouterKey
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _showOpenRouterKey = !_showOpenRouterKey),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ─── Model Selector ────────────────────────────────────
          Row(
            children: [
              Text('Model',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              if (_fetchingModels)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: _fetchModelList,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tải lại'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (!_useCustomModel && _models.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              value: _models.any((m) => m.id == _selectedModel)
                  ? _selectedModel
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              items: _models
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name,
                            overflow: TextOverflow.ellipsis, maxLines: 1),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedModel = v);
              },
            ),
            const SizedBox(height: 8),
          ],

          // Custom model text field
          if (_useCustomModel || _models.isEmpty) ...[
            TextField(
              controller: _customModelCtrl,
              decoration: const InputDecoration(
                labelText: 'Model ID (tuỳ chỉnh)',
                hintText: 'Ví dụ: models/gemini-2.0-flash',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _selectedModel = v.trim(),
            ),
            const SizedBox(height: 8),
          ],

          Row(
            children: [
              FilterChip(
                label: const Text('Nhập model tuỳ chỉnh'),
                selected: _useCustomModel,
                onSelected: (v) {
                  setState(() {
                    _useCustomModel = v;
                    if (v) {
                      _customModelCtrl.text = _selectedModel;
                    }
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ─── Current Config Summary ────────────────────────────
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cấu hình hiện tại',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _infoRow('Provider', _selectedProvider.label),
                  _infoRow(
                      'Model',
                      _useCustomModel
                          ? _customModelCtrl.text
                          : _selectedModel),
                  _infoRow(
                      'Google Key',
                      _googleKeyCtrl.text.isEmpty
                          ? '(chưa nhập)'
                          : '••••${_googleKeyCtrl.text.substring((_googleKeyCtrl.text.length - 4).clamp(0, _googleKeyCtrl.text.length))}'),
                  _infoRow(
                      'OpenRouter Key',
                      _openRouterKeyCtrl.text.isEmpty
                          ? '(mặc định)'
                          : '••••${_openRouterKeyCtrl.text.substring((_openRouterKeyCtrl.text.length - 4).clamp(0, _openRouterKeyCtrl.text.length))}'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ─── Save Button ───────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveConfig,
              icon: const Icon(Icons.save),
              label: const Text('Lưu cài đặt'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).hintColor, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
