import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const LoginScreen({super.key, required this.navigate});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscureText = true;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _submitEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final authService = ref.read(authServiceProvider);
    try {
      if (_isLogin) {
        final user = await authService.signInWithEmail(
            _emailCtrl.text.trim(), _passwordCtrl.text);
        if (user != null && mounted) widget.navigate('dashboard');
      } else {
        final user = await authService.registerWithEmail(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          _nameCtrl.text.trim(),
        );
        if (user != null && mounted) widget.navigate('dashboard');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    final authService = ref.read(authServiceProvider);
    try {
      final user = await authService.signInWithGoogle();
      if (user != null && mounted) widget.navigate('dashboard');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      _showError('Masukkan email Anda terlebih dahulu.');
      return;
    }
    setState(() => _isLoading = true);
    final authService = ref.read(authServiceProvider);
    try {
      await authService.resetPassword(_emailCtrl.text.trim());
      _showSuccess('Email reset password telah dikirim ke ${_emailCtrl.text.trim()}');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon,
      {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF0A858C), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FFFE),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD1FAF8), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF0A858C), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFFF0FDFB),
      body: Stack(
        children: [
          // ── Background decorative elements ──────────────────────────────
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A858C).withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            top: 80,
            right: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF36B8B7).withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -40,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A858C).withOpacity(0.06),
              ),
            ),
          ),
          // ── Header teal gradient strip ───────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: size.height * 0.28,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0B757B), Color(0xFF0A858C), Color(0xFF36B8B7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
            ),
          ),
          // ── Scrollable content ───────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.05),
                // Logo area (on top of gradient)
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      children: [
                        // Logo circle
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.2),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.health_and_safety_rounded,
                                    size: 36,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'VioScan BC-Care',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'AI-Assisted UV Fluorescence Screening',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: size.height * 0.06),
                // ── Form card ────────────────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A858C).withOpacity(0.08),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Tab toggle Login / Daftar ─────────────
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0FDFB),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  _tabButton('Masuk', true),
                                  _tabButton('Daftar', false),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── Name field (register only) ────────────
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              child: _isLogin
                                  ? const SizedBox.shrink()
                                  : Column(
                                      children: [
                                        TextFormField(
                                          controller: _nameCtrl,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: _inputDecoration(
                                              'Nama Lengkap',
                                              Icons.person_outline_rounded),
                                          validator: (v) => (v == null ||
                                                  v.trim().isEmpty)
                                              ? 'Nama tidak boleh kosong'
                                              : null,
                                        ),
                                        const SizedBox(height: 14),
                                      ],
                                    ),
                            ),

                            // ── Email field ───────────────────────────
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDecoration(
                                  'Email', Icons.email_outlined),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Email tidak boleh kosong';
                                }
                                if (!v.contains('@') || !v.contains('.')) {
                                  return 'Format email tidak valid';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            // ── Password field ────────────────────────
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscureText,
                              decoration: _inputDecoration(
                                'Password',
                                Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscureText
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF0A858C),
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureText = !_obscureText),
                                ),
                              ),
                              validator: (v) =>
                                  (v != null && v.length < 6)
                                      ? 'Password minimal 6 karakter'
                                      : null,
                            ),

                            // ── Forgot password ───────────────────────
                            if (_isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed:
                                      _isLoading ? null : _resetPassword,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4),
                                  ),
                                  child: const Text(
                                    'Lupa Password?',
                                    style: TextStyle(
                                      color: Color(0xFF0A858C),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(height: 20),

                            // ── Submit button ─────────────────────────
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed:
                                    _isLoading ? null : _submitEmailAuth,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0A858C),
                                  disabledBackgroundColor:
                                      const Color(0xFF0A858C).withOpacity(0.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        _isLogin ? 'Masuk' : 'Buat Akun',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Divider ATAU ──────────────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color: const Color(0xFF0A858C).withOpacity(0.2),
                              thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'ATAU',
                          style: TextStyle(
                            color:
                                const Color(0xFF0A858C).withOpacity(0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(
                              color: const Color(0xFF0A858C).withOpacity(0.2),
                              thickness: 1)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Google Sign-In button ─────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(
                            color: Color(0xFFD1D5DB), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Google "G" logo
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Image.network(
                              'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                              width: 22,
                              height: 22,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.g_mobiledata_rounded,
                                color: Color(0xFF4285F4),
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Lanjutkan dengan Google',
                            style: TextStyle(
                              color: Color(0xFF374151),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Footer note ───────────────────────────────────────────
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF0A858C).withOpacity(0.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            color: const Color(0xFF0A858C).withOpacity(0.7),
                            size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Data Anda dilindungi dan hanya digunakan untuk keperluan skrining medis. Tidak dibagikan ke pihak ketiga.',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool isLoginTab) {
    final isActive = _isLogin == isLoginTab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_isLogin != isLoginTab) {
            setState(() => _isLogin = isLoginTab);
            _formKey.currentState?.reset();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color:
                isActive ? const Color(0xFF0A858C) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF9CA3AF),
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
