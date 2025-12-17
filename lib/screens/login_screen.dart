// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo hoặc icon app
              Icon(
                Icons.shopping_cart_outlined,
                size: 120,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 32),

              // Tiêu đề
              Text(
                'Quản Lý Bán Hàng',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Ghi nợ - Quản lý khách hàng - Báo cáo doanh thu',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 64),

              // Nút đăng nhập Google
              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  return SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: auth.isLoading
                          ? null
                          : () async {
                              await auth.signInWithGoogle();

                              // Nếu đăng nhập thành công → chuyển sang Home
                              if (auth.isSignedIn && context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                                );
                              }

                              // Nếu có lỗi → hiển thị snackbar
                              if (auth.errorMessage != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(auth.errorMessage!),
                                    backgroundColor: theme.colorScheme.error,
                                  ),
                                );
                              }
                            },
                      icon: auth.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Image.asset(
                              'assets/images/google_logo.png', // Đại ca thêm file google_logo.png vào assets nếu muốn đẹp hơn
                              height: 24,
                              width: 24,
                              // Nếu chưa có ảnh, dùng icon thay thế
                              // fallback: Icon(Icons.g_mobiledata, size: 28),
                            ),
                      label: Text(
                        auth.isLoading ? 'Đang đăng nhập...' : 'Đăng nhập với Google',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // Thông tin nhỏ
              Text(
                'Đăng nhập để đồng bộ dữ liệu lên đám mây\nvà sao lưu tự động',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}