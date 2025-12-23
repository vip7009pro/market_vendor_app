import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/sheets_sync_service.dart';

class SheetsSyncScreen extends StatefulWidget {
  const SheetsSyncScreen({super.key});

  @override
  State<SheetsSyncScreen> createState() => _SheetsSyncScreenState();
}

class _SheetsSyncScreenState extends State<SheetsSyncScreen> {
  static const _prefSpreadsheetId = 'sheets_spreadsheet_id';

  bool _loading = false;
  bool _syncing = false;
  String? _spreadsheetId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _spreadsheetId = prefs.getString(_prefSpreadsheetId);
      });
    });
  }

  Future<String?> _getTokenEnsureScope() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn) return null;

    // Ensure sheets scope
    await auth.requestSheetsScope();
    final token = await auth.getAccessToken();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> _createOrAttach() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _getTokenEnsureScope();
      if (token == null) throw Exception('Không lấy được token Google.');

      final id = await SheetsSyncService().createSpreadsheet(accessToken: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSpreadsheetId, id);

      if (!mounted) return;
      setState(() {
        _spreadsheetId = id;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tạo Google Sheet')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _syncNow() async {
    final id = (_spreadsheetId ?? '').trim();
    if (id.isEmpty) {
      setState(() {
        _error = 'Chưa có Spreadsheet. Hãy bấm Tạo sheet trước.';
      });
      return;
    }

    setState(() {
      _syncing = true;
      _error = null;
    });

    try {
      final token = await _getTokenEnsureScope();
      if (token == null) throw Exception('Không lấy được token Google.');

      await SheetsSyncService().syncAll(accessToken: token, spreadsheetId: id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đồng bộ Google Sheets')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _syncing = false;
      });
    }
  }

  Future<void> _openSheet() async {
    final id = (_spreadsheetId ?? '').trim();
    if (id.isEmpty) return;
    final url = Uri.parse('https://docs.google.com/spreadsheets/d/$id');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final id = (_spreadsheetId ?? '').trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Đồng bộ Google Sheets')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Spreadsheet', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(id.isEmpty ? '(Chưa tạo)' : id),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _createOrAttach,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add),
                              label: const Text('Tạo sheet'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: id.isEmpty ? null : _openSheet,
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Mở'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _syncing ? null : _syncNow,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: Text(_syncing ? 'Đang đồng bộ...' : 'Đồng bộ ngay'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sheet sẽ được tạo các tab giống báo cáo Excel và dữ liệu được upsert theo cột id.',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
