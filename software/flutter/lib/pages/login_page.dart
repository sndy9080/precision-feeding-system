import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _konfirmasiController = TextEditingController();

  bool _isLoading = false;
  bool _isPasswordHidden = true;
  bool _isRegisterMode = false;
  String? _errorMessage;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Email dan Password tidak boleh kosong!');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('LOGIN ERROR code=${e.code} message=${e.message}');
      setState(() {
        if (e.code == 'invalid-email') {
          _errorMessage = 'Format email tidak valid.';
        } else if (e.code == 'user-disabled') {
          _errorMessage = 'Akun ini dinonaktifkan.';
        } else if (e.code == 'user-not-found') {
          _errorMessage = 'Email tidak terdaftar.';
        } else if (e.code == 'wrong-password') {
          _errorMessage = 'Password salah.';
        } else if (e.code == 'invalid-credential') {
          _errorMessage = 'Email atau password salah.';
        } else {
          _errorMessage = 'Gagal masuk: periksa email dan password.';
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Terjadi gangguan jaringan atau sistem.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _lupaPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Masukkan email terlebih dahulu.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link reset password dikirim ke $email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'user-not-found' || e.code == 'invalid-email') {
          _errorMessage = 'Email tidak terdaftar atau format salah.';
        } else {
          _errorMessage = 'Gagal kirim email reset: ${e.message}';
        }
      });
    }
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final konfirmasi = _konfirmasiController.text.trim();

    if (email.isEmpty || password.isEmpty || konfirmasi.isEmpty) {
      setState(() => _errorMessage = 'Semua field harus diisi!');
      return;
    }
    if (password != konfirmasi) {
      setState(() => _errorMessage = 'Password dan konfirmasi tidak sama!');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password minimal 6 karakter.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('REGISTER ERROR code=${e.code} message=${e.message}');
      setState(() {
        if (e.code == 'email-already-in-use') {
          _errorMessage = 'Email sudah terdaftar. Silakan login.';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'Format email tidak valid.';
        } else if (e.code == 'weak-password') {
          _errorMessage = 'Password terlalu lemah.';
        } else {
          _errorMessage = 'Gagal mendaftar: ${e.message}';
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Terjadi gangguan jaringan atau sistem.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _konfirmasiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/icon/logo.png', width: 140, height: 140),
              const SizedBox(height: 24),
              const Text(
                'Sistem Otomasi\nPakan Ternak',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isRegisterMode
                    ? 'Buat akun baru untuk mengontrol perangkat'
                    : 'Silakan login untuk mengontrol perangkat',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 40),

              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _passwordController,
                obscureText: _isPasswordHidden,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_isPasswordHidden
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(
                        () => _isPasswordHidden = !_isPasswordHidden),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),

              if (_isRegisterMode) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _konfirmasiController,
                  obscureText: _isPasswordHidden,
                  decoration: InputDecoration(
                    labelText: 'Konfirmasi Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_isRegisterMode ? _register : _login),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isRegisterMode ? 'Daftar' : 'Masuk',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => setState(() {
                          _isRegisterMode = !_isRegisterMode;
                          _errorMessage = null;
                          _konfirmasiController.clear();
                        }),
                child: Text(
                  _isRegisterMode
                      ? 'Sudah punya akun? Masuk di sini'
                      : 'Belum punya akun? Daftar di sini',
                  style: const TextStyle(color: Colors.green),
                ),
              ),

              if (!_isRegisterMode)
                TextButton(
                  onPressed: _isLoading ? null : _lupaPassword,
                  child: const Text(
                    'Lupa kata sandi?',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
