import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/skin_risk_assessment_screen.dart';
import 'screens/hardware_connection_screen.dart';
import 'screens/lesion_info_screen.dart';
import 'screens/waiting_scan_screen.dart';
import 'screens/uv_processing_screen.dart';
import 'screens/scan_result_screen.dart';
import 'screens/ai_analysis_detail_screen.dart';
import 'screens/scan_history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/about_bcc_screen.dart';
import 'screens/device_info_screen.dart';
import 'screens/emergency_assistance_screen.dart';

/// Halaman-halaman yang WAJIB login sebelum bisa diakses.
/// Jika user belum login dan mencoba navigate ke salah satu halaman ini,
/// akan diarahkan ke login screen terlebih dahulu.
const _authRequiredScreens = {
  'dashboard',
  'assessment',
  'lesion_info',
  'hardware',       // koneksi perangkat via Bluetooth — wajib login
  'waiting_scan',   // pemindaian — wajib login
  'processing',     // animasi pemrosesan — wajib login
  'result',         // hasil skrining — wajib login
  'ai_detail',
  'history',
  'history_detail', // hasil tersimpan dibuka dari Riwayat
  'profile',
  'about_bcc',
  'device',
  'emergency',
};

/// Layar yang menangani tombol back HP sendiri (PopScope di layar itu):
/// kuisioner (mundur per pertanyaan), koneksi & tunggu scan (putus Bluetooth),
/// hasil (bersihkan hasil yang sudah disimpan).
const _selfHandledBack = {
  'assessment',
  'hardware',
  'waiting_scan',
  'result',
  'history_detail',
};

/// Tujuan tombol back HP — disamakan dengan tombol kembali di dalam layar.
/// Layar yang tidak ada di sini & di atas (Beranda, login, splash) memakai
/// "tekan dua kali untuk keluar".
const _backTarget = {
  'lesion_info': 'assessment',
  'ai_detail': 'dashboard',
  'processing': 'dashboard',
  'history': 'dashboard',
  'profile': 'dashboard',
  'about_bcc': 'dashboard',
  'device': 'dashboard',
  'emergency': 'dashboard',
};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // WAJIB sebelum DateFormat pakai locale 'id_ID' di seluruh aplikasi
  // (scan_result_screen dll). Tanpa ini → LocaleDataException.
  await initializeDateFormatting('id_ID', null);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    const ProviderScope(
      child: VioScanApp(),
    ),
  );
}

class VioScanApp extends StatelessWidget {
  const VioScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VioScan BC-Care',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'sans-serif',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A858C),
        ),
        useMaterial3: true,
      ),
      home: const AppNavigator(),
    );
  }
}

class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  String _currentScreen = 'splash';
  DateTime? _lastBackPress;

  /// Tombol back / gesture kembali HP. Tanpa ini Android langsung menutup
  /// aplikasi, karena semua layar berada di satu halaman (AppNavigator).
  void _onSystemBack() {
    if (_selfHandledBack.contains(_currentScreen)) return;

    final target = _backTarget[_currentScreen];
    if (target != null) {
      navigate(target);
      return;
    }

    // Beranda / login / splash: tekan dua kali dalam 2 detik untuk keluar.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Tekan sekali lagi untuk keluar'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Navigasi terpusat dengan auth guard.
  /// Jika destination memerlukan login dan user belum login,
  /// navigate ke login dan tampilkan snackbar penjelasan.
  void navigate(String screen) {
    final user = FirebaseAuth.instance.currentUser;
    final needsAuth = _authRequiredScreens.contains(screen);

    if (needsAuth && user == null) {
      // Redirect ke login — simpan destination tidak perlu,
      // setelah login berhasil LoginScreen sudah navigate ke dashboard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _currentScreen = 'login');
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Silakan masuk terlebih dahulu untuk menggunakan fitur ini.',
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF0A858C),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      });
      return;
    }

    setState(() => _currentScreen = screen);

    final isDark = {'splash', 'processing', 'waiting_scan'}.contains(screen);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  Widget _buildScreen() {
    switch (_currentScreen) {
      case 'splash':
        return SplashScreen(navigate: navigate);
      case 'login':
        return LoginScreen(navigate: navigate);
      case 'dashboard':
        return DashboardScreen(navigate: navigate);
      case 'assessment':
        return SkinRiskAssessmentScreen(navigate: navigate);
      case 'lesion_info':
        return LesionInfoScreen(navigate: navigate);
      case 'hardware':
        return HardwareConnectionScreen(navigate: navigate);
      case 'waiting_scan':
        return WaitingScanScreen(navigate: navigate);
      case 'processing':
        return UVProcessingScreen(navigate: navigate);
      case 'result':
        return ScanResultScreen(navigate: navigate);
      case 'history_detail':
        return ScanResultScreen(navigate: navigate, fromHistory: true);
      case 'ai_detail':
        return AiAnalysisDetailScreen(navigate: navigate);
      case 'history':
        return ScanHistoryScreen(navigate: navigate);
      case 'profile':
        return ProfileScreen(navigate: navigate);
      case 'about_bcc':
        return AboutBccScreen(navigate: navigate);
      case 'device':
        return DeviceInfoScreen(navigate: navigate);
      case 'emergency':
        return EmergencyAssistanceScreen(navigate: navigate);
      default:
        return SplashScreen(navigate: navigate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Saat Firebase memuat auth state pertama kali, tahan di splash
        if (snapshot.connectionState == ConnectionState.waiting &&
            _currentScreen == 'splash') {
          return const _LoadingScreen();
        }

        // Jika Firebase mendeteksi logout dari luar (token expired dll.)
        // dan user sedang di halaman yang butuh auth → paksa ke login
        final user = snapshot.data;
        if (user == null && _authRequiredScreens.contains(_currentScreen)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _currentScreen = 'login');
          });
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onSystemBack();
          },
          child: Scaffold(
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: KeyedSubtree(
                key: ValueKey(_currentScreen),
                child: _buildScreen(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A858C),
      body: Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
        ),
      ),
    );
  }
}
