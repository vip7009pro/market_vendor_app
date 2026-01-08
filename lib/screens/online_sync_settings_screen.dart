import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../providers/auth_provider.dart';
import '../services/online_sync_service.dart';

class OnlineSyncSettingsScreen extends StatefulWidget {
  const OnlineSyncSettingsScreen({super.key});

  @override
  State<OnlineSyncSettingsScreen> createState() => _OnlineSyncSettingsScreenState();
}

class _OnlineSyncSettingsScreenState extends State<OnlineSyncSettingsScreen> {
  final _urlCtrl = TextEditingController();
  bool _loading = true;
  bool _syncing = false;
  bool _testing = false;
  String? _lastSyncAt;
  String? _lastError;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
    // Set default URL for Android emulator
    if (_urlCtrl.text.isEmpty || _urlCtrl.text == 'http://localhost:3006') {
      _urlCtrl.text = 'http://10.0.2.2:3006';
    }
  }

  Future<void> _testBackend() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      await _save();
      final baseUrl = _urlCtrl.text.trim();
      print(baseUrl);
      final uri = Uri.parse('$baseUrl/health');
      print(uri);
      final resp = await http.get(uri);

      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      final body = resp.body;
      if (!mounted) return;
      setState(() {
        _testResult = ok
            ? 'OK (${resp.statusCode})\n$body'
            : 'ERROR (${resp.statusCode})\n$body';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = 'ERROR\n$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final baseUrl = await OnlineSyncService.getBaseUrl();
      final lastAt = await OnlineSyncService.getLastSyncAt();
      final lastErr = await OnlineSyncService.getLastSyncError();
      if (!mounted) return;
      _urlCtrl.text = baseUrl;
      setState(() {
        _lastSyncAt = lastAt;
        _lastError = lastErr;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final v = _urlCtrl.text.trim();
    if (v.isEmpty) return;
    await OnlineSyncService.setBaseUrl(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu backend URL')),
    );
  }

  Future<void> _syncNow() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn cần đăng nhập để đồng bộ')),
      );
      return;
    }

    setState(() => _syncing = true);
    try {
      await _save();
      await OnlineSyncService.syncNow(auth: auth, allowBackoff: false);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đồng bộ xong')),
      );
    } catch (e) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi đồng bộ: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đồng bộ Online'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Backend URL',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _urlCtrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            hintText: 'http://localhost:3006',
                            prefixIcon: Icon(Icons.link),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _syncing ? null : _save,
                                icon: const Icon(Icons.save),
                                label: const Text('Lưu'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _syncing ? null : _syncNow,
                                icon: _syncing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sync),
                                label: Text(_syncing ? 'Đang đồng bộ' : 'Sync now'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: (_syncing || _testing) ? null : _testBackend,
                            icon: _testing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_tethering),
                            label: Text(_testing ? 'Đang test...' : 'Test kết nối backend'),
                          ),
                        ),

                        if (_testResult != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                            child: Text(
                              _testResult!,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trạng thái',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.schedule, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Last sync: ${_lastSyncAt ?? '-'}'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _lastError == null ? Icons.check_circle_outline : Icons.error_outline,
                              size: 18,
                              color: _lastError == null ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Last error: ${_lastError ?? '-'}'),
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
  }
}
