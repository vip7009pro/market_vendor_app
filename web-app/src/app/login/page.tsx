'use client';

import React, { useState, useEffect, Suspense } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import api from '@/lib/api';

function LoginForm() {
  const { user, login, register, loading } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  
  const [isRegister, setIsRegister] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    // If user is already logged in, redirect to dashboard
    if (user) {
      router.push('/dashboard');
    }
  }, [user, router]);

  useEffect(() => {
    const mode = searchParams.get('mode');
    if (mode === 'register') {
      setIsRegister(true);
    } else {
      setIsRegister(false);
    }
  }, [searchParams]);

  useEffect(() => {
    const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID || '794292505696-91jr15omjtkfod6rh44k7figsrmsb52t.apps.googleusercontent.com';

    interface GoogleAccounts {
      id: {
        initialize: (config: {
          client_id: string;
          callback: (response: { credential: string }) => Promise<void>;
          auto_select?: boolean;
        }) => void;
        renderButton: (
          parent: HTMLElement | null,
          options: {
            theme?: string;
            size?: string;
            text?: string;
            shape?: string;
            width?: number;
          }
        ) => void;
      };
    }

    const initializeGoogleSignIn = () => {
      const google = (window as unknown as { google?: { accounts: GoogleAccounts } }).google;
      if (google) {
        google.accounts.id.initialize({
          client_id: googleClientId,
          callback: async (response: { credential: string }) => {
            setErrorMsg('');
            setSubmitting(true);
            try {
              const res = await api.loginGoogle(response.credential);
              if (res.token) {
                localStorage.setItem('token', res.token);
                window.location.href = '/dashboard';
              } else {
                throw new Error('Đăng nhập Google thất bại (không nhận được Token)');
              }
            } catch (err: unknown) {
              const error = err as Error;
              setErrorMsg(error.message || 'Lỗi đăng nhập Google');
              setSubmitting(false);
            }
          },
          auto_select: false,
        });

        google.accounts.id.renderButton(
          document.getElementById('googleSignInButton'),
          {
            theme: 'filled_black',
            size: 'large',
            text: isRegister ? 'signup_with' : 'signin_with',
            shape: 'rectangular',
            width: 320,
          }
        );
      }
    };

    if (!(window as unknown as { google?: unknown }).google) {
      const script = document.createElement('script');
      script.src = 'https://accounts.google.com/gsi/client';
      script.async = true;
      script.defer = true;
      script.onload = initializeGoogleSignIn;
      document.body.appendChild(script);
    } else {
      initializeGoogleSignIn();
    }
  }, [isRegister]);

  const handleDemoLogin = async () => {
    setErrorMsg('');
    setSubmitting(true);
    try {
      try {
        await register('demo@marketvendor.vn', 'demo123456', 'Chủ cửa hàng Demo');
      } catch {
        await login('demo@marketvendor.vn', 'demo123456');
      }
    } catch (err: unknown) {
      const error = err as Error;
      setErrorMsg(error.message || 'Lỗi đăng nhập tài khoản Demo');
      setSubmitting(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');
    
    if (!email || !password) {
      setErrorMsg('Vui lòng điền đầy đủ email và mật khẩu');
      return;
    }

    if (isRegister && !name) {
      setErrorMsg('Vui lòng nhập tên của bạn');
      return;
    }

    setSubmitting(true);
    try {
      if (isRegister) {
        await register(email, password, name);
      } else {
        await login(email, password);
      }
    } catch (err: unknown) {
      const error = err as Error;
      setErrorMsg(error.message || 'Đã xảy ra lỗi, vui lòng thử lại');
      setSubmitting(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#0f172a] text-[#f1f5f9] font-sans flex items-center justify-center relative overflow-hidden px-4">
      {/* Background radial glow */}
      <div className="absolute inset-0 z-0 bg-[radial-gradient(circle_at_center,rgba(99,102,241,0.1),transparent_50%)]" />
      
      <div className="w-full max-w-md relative z-10 animate-fade-in-up">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <Link href="/" className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-tr from-indigo-500 to-cyan-400 flex items-center justify-center font-bold text-white text-2xl shadow-lg shadow-indigo-500/20">
              M
            </div>
            <div>
              <h1 className="font-bold text-xl leading-none tracking-tight text-white">Market Vendor</h1>
              <span className="text-[10px] text-cyan-400 uppercase tracking-widest font-semibold">Web App</span>
            </div>
          </Link>
        </div>

        {/* Card Form */}
        <div className="glass rounded-2xl border border-white/10 p-8 shadow-2xl relative overflow-hidden">
          <h2 className="text-2xl font-bold text-white text-center mb-6">
            {isRegister ? 'Tạo tài khoản mới' : 'Đăng nhập vào hệ thống'}
          </h2>

          {errorMsg && (
            <div className="mb-5 p-3 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs text-center">
              ⚠️ {errorMsg}
            </div>
          )}

          {/* Google Sign In Button */}
          <div className="w-full mb-5 flex justify-center">
            <div id="googleSignInButton" className="w-full flex justify-center min-h-[44px]"></div>
          </div>

          {/* Divider */}
          <div className="relative mb-5 text-center">
            <span className="absolute inset-x-0 top-1/2 border-t border-slate-800"></span>
            <span className="relative bg-[#0f172a] px-3 text-[10px] text-slate-500 uppercase tracking-wider font-semibold">hoặc dùng Email</span>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {isRegister && (
              <div>
                <label className="block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2">Tên của bạn</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Nguyễn Văn A"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  disabled={submitting}
                />
              </div>
            )}

            <div>
              <label className="block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2">Email</label>
              <input
                type="email"
                className="input"
                placeholder="example@gmail.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={submitting}
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-400 uppercase tracking-wider mb-2">Mật khẩu</label>
              <input
                type="password"
                className="input"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={submitting}
              />
            </div>

            <button
              type="submit"
              className="btn btn-primary w-full btn-lg font-bold shadow-glow mt-2 flex items-center justify-center gap-2"
              disabled={submitting}
            >
              {submitting ? (
                <>
                  <span className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin"></span>
                  Đang xử lý...
                </>
              ) : isRegister ? (
                'Đăng ký tài khoản'
              ) : (
                'Đăng nhập'
              )}
            </button>
          </form>

          {/* Divider */}
          <div className="relative my-6 text-center">
            <span className="absolute inset-x-0 top-1/2 border-t border-slate-800"></span>
            <span className="relative bg-[#0f172a] px-3 text-xs text-slate-500 uppercase tracking-wider font-semibold">hoặc</span>
          </div>

          {/* Quick Demo Login */}
          <button
            type="button"
            onClick={handleDemoLogin}
            disabled={submitting}
            className="w-full mb-6 py-2.5 rounded-lg border border-indigo-500/20 bg-indigo-500/10 hover:bg-indigo-500/20 transition-colors text-indigo-300 font-bold text-xs flex items-center justify-center gap-2 cursor-pointer"
          >
            ⚡ Đăng nhập nhanh với tài khoản Demo
          </button>

          {/* Toggle login/register */}
          <div className="text-center text-sm text-slate-400">
            {isRegister ? (
              <>
                Đã có tài khoản?{' '}
                <button
                  type="button"
                  onClick={() => {
                    setIsRegister(false);
                    setErrorMsg('');
                  }}
                  className="text-indigo-400 hover:text-indigo-300 font-semibold"
                >
                  Đăng nhập ngay
                </button>
              </>
            ) : (
              <>
                Chưa có tài khoản?{' '}
                <button
                  type="button"
                  onClick={() => {
                    setIsRegister(true);
                    setErrorMsg('');
                  }}
                  className="text-indigo-400 hover:text-indigo-300 font-semibold"
                >
                  Đăng ký miễn phí
                </button>
              </>
            )}
          </div>
        </div>

        {/* Back Link */}
        <div className="text-center mt-6">
          <Link href="/" className="text-sm text-slate-500 hover:text-slate-400 transition-colors">
            ← Quay lại trang chủ
          </Link>
        </div>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-[#0f172a] text-[#f1f5f9] flex items-center justify-center font-sans">
        <div className="flex flex-col items-center gap-4">
          <div className="w-12 h-12 border-4 border-indigo-500/30 border-t-indigo-500 rounded-full animate-spin"></div>
          <p className="text-slate-400 text-sm">Đang tải trang đăng nhập...</p>
        </div>
      </div>
    }>
      <LoginForm />
    </Suspense>
  );
}
