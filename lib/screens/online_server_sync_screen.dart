import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';
import '../services/database_service.dart';
import '../services/online_sync_service.dart';
import '../services/online_api_service.dart';

class OnlineServerSyncScreen extends StatefulWidget {
  const OnlineServerSyncScreen({super.key});

  @override
  State<OnlineServerSyncScreen> createState() => _OnlineServerSyncScreenState();
}

class _OnlineServerSyncScreenState extends State<OnlineServerSyncScreen> {
  final _urlCtrl = TextEditingController();
  bool _loading = true;
  bool _testingConnection = false;
  bool _isOnlineMode = false;
  bool _isUploading = false;
  bool _isDownloading = false;

  String? _connectionStatusText;
  bool? _connectionStatusOk;
  int? _latencyMs;

  String? _lastSyncAt;
  String? _lastError;

  // Counters
  Map<String, int> _localCounts = {};
  bool _loadingCounts = false;

  // Upload/Download progress
  double _actionProgress = 0.0;
  String _actionStatusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      final baseUrl = await OnlineSyncService.getBaseUrl();
      final isOnline = await OnlineSyncService.isOnlineMode();
      final lastAt = await OnlineSyncService.getLastSyncAt();
      final lastErr = await OnlineSyncService.getLastSyncError();

      if (!mounted) return;
      _urlCtrl.text = baseUrl;
      _isOnlineMode = isOnline;
      _lastSyncAt = lastAt;
      _lastError = lastErr;

      await _refreshLocalCounts();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshLocalCounts() async {
    setState(() => _loadingCounts = true);
    try {
      if (_isOnlineMode) {
        final counts = await OnlineApiService.instance.getEntityCounts();
        if (!mounted) return;
        setState(() {
          _localCounts = counts;
        });
        return;
      }

      final db = DatabaseService.instance.db;
      final pRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM products WHERE deletedAt IS NULL OR TRIM(deletedAt) = ''",
      );
      final cRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM customers WHERE deletedAt IS NULL OR TRIM(deletedAt) = ''",
      );
      final sRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM sales WHERE deletedAt IS NULL OR TRIM(deletedAt) = ''",
      );
      final dRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM debts WHERE deletedAt IS NULL OR TRIM(deletedAt) = ''",
      );
      final eRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM expenses WHERE deletedAt IS NULL OR TRIM(deletedAt) = ''",
      );

      if (!mounted) return;
      setState(() {
        _localCounts = {
          'products': (pRows.first['c'] as num?)?.toInt() ?? 0,
          'customers': (cRows.first['c'] as num?)?.toInt() ?? 0,
          'sales': (sRows.first['c'] as num?)?.toInt() ?? 0,
          'debts': (dRows.first['c'] as num?)?.toInt() ?? 0,
          'expenses': (eRows.first['c'] as num?)?.toInt() ?? 0,
        };
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingCounts = false);
    }
  }

  Future<void> _saveUrl() async {
    final v = _urlCtrl.text.trim();
    if (v.isEmpty) return;
    await OnlineSyncService.setBaseUrl(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu cấu hình địa chỉ máy chủ')),
    );
  }

  Future<void> _resetDefaultUrl() async {
    setState(() {
      _urlCtrl.text = OnlineSyncService.defaultBaseUrl;
    });
    await _saveUrl();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionStatusText = null;
      _connectionStatusOk = null;
      _latencyMs = null;
    });

    try {
      await _saveUrl();
      final result = await OnlineSyncService.testConnection(
        _urlCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _connectionStatusOk = result['ok'] == true;
        _connectionStatusText = result['message'] as String;
        _latencyMs = result['latencyMs'] as int?;
      });
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Future<void> _toggleOnlineMode(bool targetMode) async {
    final title = targetMode ? 'Bật Chế độ Online' : 'Chuyển về Chế độ Offline';
    final desc =
        targetMode
            ? 'Chế độ Online sẽ sử dụng dữ liệu máy chủ PostgreSQL (ruougaohoatuoi.ddns.net).\n\n'
                'Toàn bộ dữ liệu offline cũ của bạn vẫn được lưu giữ an toàn 100% trên máy.'
            : 'Chuyển về Chế độ Offline để tiếp tục sử dụng kho dữ liệu cục bộ cũ trên máy.\n\n'
                'Dữ liệu offline sẽ được nạp lại nguyên vẹn như trước.';

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(desc),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(targetMode ? 'Bật Online' : 'Chuyển Offline'),
              ),
            ],
          ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await OnlineSyncService.setOnlineMode(targetMode);
      _isOnlineMode = targetMode;

      // Nạp lại tất cả providers để UI phản ánh đúng kho dữ liệu đang kích hoạt
      if (!mounted) return;
      await Future.wait([
        context.read<ProductProvider>().load(),
        context.read<CustomerProvider>().load(),
        context.read<SaleProvider>().load(),
        context.read<DebtProvider>().load(),
      ]);

      if (targetMode) {
        // Tự động kéo dữ liệu snapshot mới nhất từ PostgreSQL về nạp vào máy
        try {
          final auth = context.read<AuthProvider>();
          await OnlineSyncService.downloadAllServerToOffline(
            auth: auth,
            toOfflineOnly: false,
          );
          if (mounted) {
            await Future.wait([
              context.read<ProductProvider>().load(),
              context.read<CustomerProvider>().load(),
              context.read<SaleProvider>().load(),
              context.read<DebtProvider>().load(),
            ]);
          }
        } catch (dlErr) {
          debugPrint('Không thể tải snapshot khi bật Online: $dlErr');
        }
      }

      await _refreshLocalCounts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            targetMode
                ? 'Đã kích hoạt Chế độ Online (PostgreSQL)'
                : 'Đã quay lại Chế độ Offline an toàn',
          ),
          backgroundColor:
              targetMode ? Colors.green[700] : Colors.blueGrey[700],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi chuyển chế độ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Nút 1: Tải toàn bộ dữ liệu offline lên máy chủ PostgreSQL
  Future<void> _uploadAllToServer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text(
              'Tải toàn bộ lên Máy chủ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Hệ thống sẽ gom toàn bộ danh mục sản phẩm, khách hàng, hóa đơn, công nợ, chi phí '
              'từ thiết bị và tải lên máy chủ PostgreSQL (ruougaohoatuoi.ddns.net).\n\n'
              'Thao tác này dùng để chuẩn bị chuyển sang dùng hoàn toàn online.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Tải lên ngay'),
              ),
            ],
          ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isUploading = true;
      _actionProgress = 0.0;
      _actionStatusMessage = 'Đang chuẩn bị...';
    });

    try {
      final auth = context.read<AuthProvider>();
      final result = await OnlineSyncService.uploadAllOfflineToServer(
        auth: auth,
        onProgress: (msg, prog) {
          if (mounted) {
            setState(() {
              _actionStatusMessage = msg;
              _actionProgress = prog;
            });
          }
        },
      );

      // Tự động kéo snapshot mới nhất về nạp vào DB đang hoạt động và cập nhật toàn bộ màn hình
      try {
        await OnlineSyncService.downloadAllServerToOffline(
          auth: auth,
          toOfflineOnly: false,
        );
        if (mounted) {
          await Future.wait([
            context.read<ProductProvider>().load(),
            context.read<CustomerProvider>().load(),
            context.read<SaleProvider>().load(),
            context.read<DebtProvider>().load(),
          ]);
          await _refreshLocalCounts();
        }
      } catch (dlErr) {
        debugPrint('Tự động nạp snapshot sau upload gặp lỗi: $dlErr');
      }

      final lastAt = await OnlineSyncService.getLastSyncAt();
      if (!mounted) return;
      setState(() {
        _lastSyncAt = lastAt;
        _lastError = null;
      });

      await showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              icon: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 48,
              ),
              title: const Text('Tải lên Thành công!'),
              content: Text(result['message'] as String),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Đóng'),
                ),
              ],
            ),
      );
    } catch (e) {
      final lastErr = await OnlineSyncService.getLastSyncError();
      if (!mounted) return;
      setState(() => _lastError = lastErr);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải lên: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _actionProgress = 0.0;
          _actionStatusMessage = '';
        });
      }
    }
  }

  /// Nút 2: Đồng bộ từ Server về máy Offline
  Future<void> _downloadAllToOffline() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text(
              'Đồng bộ từ Server về Offline',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'Hệ thống sẽ tải toàn bộ dữ liệu mới nhất từ máy chủ PostgreSQL về lưu vào bộ nhớ offline trên máy.\n\n'
              'Mục đích: Đề phòng mất dữ liệu và giữ bản sao lưu đầy đủ nhất trên thiết bị.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.cloud_download),
                label: const Text('Tải về máy'),
              ),
            ],
          ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isDownloading = true;
      _actionProgress = 0.0;
      _actionStatusMessage = 'Đang kết nối...';
    });

    try {
      final auth = context.read<AuthProvider>();
      final result = await OnlineSyncService.downloadAllServerToOffline(
        auth: auth,
        toOfflineOnly: false,
        onProgress: (msg, prog) {
          if (mounted) {
            setState(() {
              _actionStatusMessage = msg;
              _actionProgress = prog;
            });
          }
        },
      );

      final lastAt = await OnlineSyncService.getLastSyncAt();
      if (!mounted) return;
      setState(() {
        _lastSyncAt = lastAt;
        _lastError = null;
      });

      // Luôn reload providers để UI cập nhật ngay lập tức danh sách SP, đơn hàng, khách hàng
      await Future.wait([
        context.read<ProductProvider>().load(),
        context.read<CustomerProvider>().load(),
        context.read<SaleProvider>().load(),
        context.read<DebtProvider>().load(),
      ]);
      await _refreshLocalCounts();

      if (!mounted) return;
      await showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              icon: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 48,
              ),
              title: const Text('Đồng bộ về máy Thành công!'),
              content: Text(result['message'] as String),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Đóng'),
                ),
              ],
            ),
      );
    } catch (e) {
      final lastErr = await OnlineSyncService.getLastSyncError();
      if (!mounted) return;
      setState(() => _lastError = lastErr);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi đồng bộ về máy: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _actionProgress = 0.0;
          _actionStatusMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWorking = _isUploading || _isDownloading || _loading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đồng bộ Máy chủ PostgreSQL'),
        actions: [
          IconButton(
            onPressed: isWorking ? null : _loadInitialData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Tùy chọn',
            onSelected: (val) async {
              if (val == 'reset_jwt') {
                final messenger = ScaffoldMessenger.of(context);
                await OnlineSyncService.clearJwt();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Đã xóa token đăng nhập cũ. Hệ thống sẽ tự động cấp token mới khi kết nối.',
                    ),
                    backgroundColor: Colors.blueGrey,
                  ),
                );
              }
            },
            itemBuilder:
                (ctx) => [
                  const PopupMenuItem(
                    value: 'reset_jwt',
                    child: Row(
                      children: [
                        Icon(Icons.key_off, size: 20),
                        SizedBox(width: 8),
                        Text('Làm mới phiên đăng nhập (Token)'),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ─── 1. CARD CHẾ ĐỘ ONLINE / OFFLINE ────────────────────────
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color:
                            _isOnlineMode
                                ? Colors.green.withOpacity(0.5)
                                : Colors.orange.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    color:
                        _isOnlineMode
                            ? Colors.green.withOpacity(0.06)
                            : Colors.orange.withOpacity(0.06),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      _isOnlineMode
                                          ? Colors.green.withOpacity(0.15)
                                          : Colors.orange.withOpacity(0.15),
                                ),
                                child: Icon(
                                  _isOnlineMode
                                      ? Icons.cloud_done
                                      : Icons.cloud_off,
                                  color:
                                      _isOnlineMode
                                          ? Colors.green[700]
                                          : Colors.orange[800],
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isOnlineMode
                                          ? 'CHẾ ĐỘ ONLINE'
                                          : 'CHẾ ĐỘ OFFLINE',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color:
                                                _isOnlineMode
                                                    ? Colors.green[800]
                                                    : Colors.orange[900],
                                          ),
                                    ),
                                    Text(
                                      _isOnlineMode
                                          ? 'Dữ liệu kết nối trực tiếp PostgreSQL'
                                          : 'Dữ liệu lưu an toàn trên máy cục bộ',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _isOnlineMode,
                                activeColor: Colors.green,
                                onChanged: isWorking ? null : _toggleOnlineMode,
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: Colors.blueGrey[600],
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isOnlineMode
                                      ? 'Toàn bộ dữ liệu offline từ trước vẫn được bảo lưu trên thiết bị. Bạn có thể gạt công tắc để quay về offline bất kỳ lúc nào.'
                                      : 'Bạn đang sử dụng kho dữ liệu offline cũ. Khi muốn chuyển hẳn sang online, hãy bấm Tải lên máy chủ trước khi bật công tắc.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.blueGrey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── 2. CARD ĐỊA CHỈ MÁY CHỦ (ruougaohoatuoi.ddns.net) ────────────────
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Địa chỉ Máy chủ Backend',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _urlCtrl,
                            keyboardType: TextInputType.url,
                            enabled: !isWorking,
                            decoration: InputDecoration(
                              hintText: 'http://ruougaohoatuoi.ddns.net:3007',
                              prefixIcon: const Icon(Icons.dns_outlined),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.restore, size: 20),
                                tooltip:
                                    'Đặt lại mặc định ruougaohoatuoi.ddns.net',
                                onPressed: isWorking ? null : _resetDefaultUrl,
                              ),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      isWorking || _testingConnection
                                          ? null
                                          : _testConnection,
                                  icon:
                                      _testingConnection
                                          ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Icon(
                                            Icons.network_ping,
                                            size: 18,
                                          ),
                                  label: Text(
                                    _testingConnection
                                        ? 'Đang kiểm tra...'
                                        : 'Kiểm tra kết nối',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: isWorking ? null : _saveUrl,
                                child: const Text('Lưu'),
                              ),
                            ],
                          ),

                          if (_connectionStatusText != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _connectionStatusOk == true
                                        ? Colors.green.withOpacity(0.12)
                                        : Colors.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      _connectionStatusOk == true
                                          ? Colors.green
                                          : Colors.red,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _connectionStatusOk == true
                                        ? Icons.check_circle
                                        : Icons.error,
                                    color:
                                        _connectionStatusOk == true
                                            ? Colors.green[700]
                                            : Colors.red,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _latencyMs != null
                                          ? '$_connectionStatusText (${_latencyMs}ms)'
                                          : _connectionStatusText!,
                                      style: TextStyle(
                                        color:
                                            _connectionStatusOk == true
                                                ? Colors.green[900]
                                                : Colors.red[900],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── 3. THAO TÁC ĐỒNG BỘ DỮ LIỆU (UPLOAD / DOWNLOAD) ────────
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thao tác Đồng bộ Dữ liệu',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tải dữ liệu lên máy chủ online hoặc kéo dữ liệu máy chủ về dự phòng trên máy.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Nút Tải lên (Sync Up 1 chiều)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: isWorking ? null : _uploadAllToServer,
                              icon:
                                  _isUploading
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : const Icon(Icons.cloud_upload),
                              label: Text(
                                _isUploading
                                    ? 'Đang tải lên server...'
                                    : 'Tải toàn bộ lên Server (1 chiều)',
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Nút Tải về (Sync Down về Offline)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed:
                                  isWorking ? null : _downloadAllToOffline,
                              icon:
                                  _isDownloading
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.cloud_download),
                              label: Text(
                                _isDownloading
                                    ? 'Đang tải về máy...'
                                    : 'Đồng bộ từ Server về Offline',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),

                          // Progress indicator bar if working
                          if (_isUploading || _isDownloading) ...[
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value:
                                  _actionProgress > 0 ? _actionProgress : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _actionStatusMessage,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── 4. CARD ĐỐI CHIẾU DỮ LIỆU CỤC BỘ ──────────────────────
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Số lượng Dữ liệu Cục bộ',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_loadingCounts)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: _refreshLocalCounts,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildCounterRow(
                            'Sản phẩm',
                            _localCounts['products'] ?? 0,
                            Icons.inventory_2_outlined,
                          ),
                          const Divider(height: 14),
                          _buildCounterRow(
                            'Khách hàng & NCC',
                            _localCounts['customers'] ?? 0,
                            Icons.people_outline,
                          ),
                          const Divider(height: 14),
                          _buildCounterRow(
                            'Đơn bán hàng',
                            _localCounts['sales'] ?? 0,
                            Icons.shopping_bag_outlined,
                          ),
                          const Divider(height: 14),
                          _buildCounterRow(
                            'Hồ sơ Công nợ',
                            _localCounts['debts'] ?? 0,
                            Icons.account_balance_wallet_outlined,
                          ),
                          const Divider(height: 14),
                          _buildCounterRow(
                            'Khoản Chi phí',
                            _localCounts['expenses'] ?? 0,
                            Icons.receipt_long_outlined,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── 5. TRẠNG THÁI LẦN ĐỒNG BỘ CUỐI ────────────────────────
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nhật ký Trạng thái',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Lần đồng bộ cuối: ${_lastSyncAt ?? 'Chưa thực hiện'}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          if (_lastError != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Lỗi: $_lastError',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildCounterRow(String label, int count, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blueGrey),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blueGrey.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
