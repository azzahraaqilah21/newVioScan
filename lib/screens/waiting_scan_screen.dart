import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/device_provider.dart';
import '../services/device_service.dart';

class WaitingScanScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;

  const WaitingScanScreen({
    super.key,
    required this.navigate,
  });

  @override
  ConsumerState<WaitingScanScreen> createState() =>
      _WaitingScanScreenState();
}

class _WaitingScanScreenState extends ConsumerState<WaitingScanScreen> {
  String _selectedMode = 'uv';

  /// Alat sudah disiapkan dan scan_ready diterima.
  bool _isPrepared = false;
  bool _prepareRequested = false;
  String? _lastError;

  StreamSubscription<DeviceConnectionState>? _statusSubscription;
  StreamSubscription<bool>? _preparedSubscription;
  bool _navigating = false;
  late final DeviceService _service;

  @override
  void initState() {
    super.initState();
    _service = ref.read(deviceServiceProvider);

    // Listener status perangkat.
    _statusSubscription =
        ref.read(deviceStatusProvider.notifier).stream.listen(
      _handleDeviceStatus,
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _lastError = 'Gagal membaca status perangkat: $error';
          _isPrepared = false;
          _prepareRequested = false;
        });
      },
    );

    // Listener konfirmasi kesiapan dari DeviceService.
    _preparedSubscription =
        ref.read(deviceServiceProvider).preparedStream.listen(
      (prepared) {
        if (!mounted) return;

        setState(() {
          _isPrepared = prepared;
          _prepareRequested = false;

          if (prepared) {
            _lastError = null;
          }
        });
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _isPrepared = false;
          _prepareRequested = false;
          _lastError = 'Gagal menerima status kesiapan alat: $error';
        });
      },
    );

    // Sinkronisasi jika alat sudah siap sebelum listener dipasang.
    final service = ref.read(deviceServiceProvider);
    if (service.isPrepared) {
      _isPrepared = true;
    }
  }

  void _handleDeviceStatus(DeviceConnectionState next) {
    if (!mounted) return;

    if (next == DeviceConnectionState.done) {
      final hwResult = ref.read(latestHardwareResultProvider);

      if (hwResult != null) {
        _navigateOnce('result');
      } else {
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted || _navigating) return;

          final result = ref.read(latestHardwareResultProvider);

          if (result != null) {
            _navigateOnce('result');
          } else {
            setState(() {
              _lastError =
                  'Koneksi selesai tetapi hasil tidak diterima dari alat. '
                  'Silakan coba lagi.';
              _isPrepared = false;
              _prepareRequested = false;
            });
          }
        });
      }
    } else if (next == DeviceConnectionState.error) {
      setState(() {
        _lastError =
            ref.read(deviceServiceProvider).lastErrorMessage ??
            'Alat melaporkan kesalahan. Coba lagi.';
        _isPrepared = false;
        _prepareRequested = false;
      });
    } else if (next == DeviceConnectionState.connected) {
      // Kesiapan alat ditentukan oleh scan_ready,
      // bukan sekadar status connected.
    }
  }

  void _navigateOnce(String destination) {
    if (!mounted || _navigating) return;

    _navigating = true;
    widget.navigate(destination);
  }

  /// Kirim PREPARE_SCAN tanpa mengambil foto.
  Future<void> _prepareDevice() async {
    if (!mounted || _prepareRequested) return;

    setState(() {
      _lastError = null;
      _isPrepared = false;
      _prepareRequested = true;
    });

    try {
      await ref
          .read(deviceStatusProvider.notifier)
          .sendPrepareScanCommand(mode: _selectedMode);

      if (!mounted) return;

      final service = ref.read(deviceServiceProvider);

      // Tangani simulasi atau konfirmasi yang sudah diterima.
      if (service.isPrepared) {
        setState(() {
          _isPrepared = true;
          _prepareRequested = false;
        });
      } else if (service.lastErrorMessage != null) {
        setState(() {
          _lastError = service.lastErrorMessage;
          _prepareRequested = false;
        });
      }

      // Pada koneksi nyata, tunggu preparedStream/scan_ready.
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _lastError = 'Gagal menyiapkan alat: $e';
        _prepareRequested = false;
        _isPrepared = false;
      });
    }
  }

  /// Pemindaian manual dari tombol HP.
  Future<void> _startScanFromPhone() async {
    if (!mounted || !_isPrepared) return;

    setState(() {
      _lastError = null;
    });

    try {
      await ref
          .read(deviceStatusProvider.notifier)
          .sendStartScanCommand(mode: _selectedMode);

      if (!mounted) return;

      final error = ref.read(deviceServiceProvider).lastErrorMessage;

      if (error != null) {
        setState(() {
          _lastError = error;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _lastError = 'Gagal memulai pemindaian: $e';
      });
    }
  }

  void _cancel() {
    ref.read(deviceStatusProvider.notifier).disconnect();
    _navigateOnce('dashboard');
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _preparedSubscription?.cancel();
    // Keluar dari halaman Pemindaian → LED UV/putih mati & tombol fisik
    // alat terkunci lagi sampai halaman ini dibuka lewat alur skrining.
    _service.sendEndScanCommand();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceStatusProvider);
    final progressAsync = ref.watch(scanProgressProvider);

    final isScanning =
        deviceState == DeviceConnectionState.capturing ||
        deviceState == DeviceConnectionState.transferring;

    final ScanProgress? latestProgress = progressAsync.value;

    final waitingForButton = _isPrepared && !isScanning;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        if (isScanning) {
          ref.read(deviceStatusProvider.notifier).disconnect();
          _navigateOnce('dashboard');
        } else {
          _navigateOnce('hardware');
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111827),
        appBar: AppBar(
          title: const Text(
            'Pemindaian Lesi Kulit',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              if (isScanning) {
                ref.read(deviceStatusProvider.notifier).disconnect();
                _navigateOnce('dashboard');
              } else {
                _navigateOnce('hardware');
              }
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // MODE SELECTOR
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _ModeButton(
                        label: 'UV Fluorosensi (365nm)',
                        icon: Icons.wb_twilight_rounded,
                        selected: _selectedMode == 'uv',
                        enabled: !isScanning && !_prepareRequested,
                        onTap: () {
                          setState(() {
                            _selectedMode = 'uv';
                          });

                          if (_isPrepared) {
                            _prepareDevice();
                          }
                        },
                      ),
                      _ModeButton(
                        label: 'Dermoskopi Putih',
                        icon: Icons.light_mode_rounded,
                        selected: _selectedMode == 'white',
                        enabled: !isScanning && !_prepareRequested,
                        onTap: () {
                          setState(() {
                            _selectedMode = 'white';
                          });

                          if (_isPrepared) {
                            _prepareDevice();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // VISUAL UTAMA
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isScanning) ...[
                            _PulsingRing(size: 240, opacity: 0.15),
                            _PulsingRing(size: 180, opacity: 0.25),
                          ],
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: _selectedMode == 'uv'
                                    ? [
                                        const Color(0xFF36B8B7),
                                        const Color(0xFF0A858C),
                                      ]
                                    : [
                                        const Color(0xFFF59E0B),
                                        const Color(0xFFD97706),
                                      ],
                              ),
                              boxShadow:
                                  isScanning || waitingForButton
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF77DAD7)
                                                .withOpacity(0.6),
                                            blurRadius: 30,
                                            spreadRadius: 5,
                                          ),
                                        ]
                                      : [],
                            ),
                            child: Icon(
                              deviceState ==
                                      DeviceConnectionState.transferring
                                  ? Icons.sync_rounded
                                  : deviceState ==
                                          DeviceConnectionState.capturing
                                      ? Icons.camera_rounded
                                      : waitingForButton
                                          ? Icons.touch_app_rounded
                                          : Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 36),

                      Text(
                        _prepareRequested && !_isPrepared
                            ? 'Menyiapkan alat...'
                            : _statusText(deviceState, isScanning),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              deviceState == DeviceConnectionState.error
                                  ? const Color(0xFFF87171)
                                  : Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                        ),
                        child: Text(
                          _prepareRequested && !_isPrepared
                              ? 'Menunggu konfirmasi kesiapan dari Raspberry Pi...'
                              : _subText(
                                  deviceState,
                                  isScanning,
                                  latestProgress,
                                ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 13.5,
                            height: 1.5,
                          ),
                        ),
                      ),

                      // PROGRESS BAR
                      if (isScanning) ...[
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                          ),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: latestProgress != null
                                      ? latestProgress.percent / 100.0
                                      : null,
                                  backgroundColor:
                                      Colors.white.withOpacity(0.12),
                                  valueColor:
                                      const AlwaysStoppedAnimation(
                                    Color(0xFF77DAD7),
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    latestProgress != null
                                        ? 'Langkah ${latestProgress.step}/${latestProgress.total}'
                                        : 'Menunggu respons...',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withOpacity(0.5),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  Text(
                                    latestProgress != null
                                        ? '${latestProgress.percent}%'
                                        : '',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withOpacity(0.5),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // AREA TOMBOL
              if (!isScanning)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_lastError != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF7F1D1D).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFF87171),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFF87171),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _lastError!,
                                  style: const TextStyle(
                                    color: Color(0xFFFECACA),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _prepareRequested
                              ? null
                              : _isPrepared
                                  ? _startScanFromPhone
                                  : _prepareDevice,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isPrepared
                                ? const Color(0xFFD97706)
                                : const Color(0xFF0A858C),
                            disabledBackgroundColor:
                                const Color(0xFF374151),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _prepareRequested
                                    ? Icons.hourglass_top_rounded
                                    : _isPrepared
                                        ? Icons.touch_app_rounded
                                        : Icons.power_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _prepareRequested
                                    ? 'Menyiapkan Alat...'
                                    : _isPrepared
                                        ? 'Pindai Sekarang (dari HP)'
                                        : 'Siapkan Alat (${_selectedMode.toUpperCase()})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      Text(
                        _isPrepared
                            ? 'Tekan Pindai Sekarang untuk mengambil gambar dari HP.'
                            : 'Siapkan alat sesuai mode, lalu tunggu konfirmasi dari Raspberry Pi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              if (isScanning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Text(
                    'Menunggu respons Raspberry Pi…',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(
    DeviceConnectionState deviceState,
    bool isScanning,
  ) {
    if (deviceState == DeviceConnectionState.error) return 'Scan gagal';

    if (deviceState == DeviceConnectionState.capturing) {
      return 'Menganalisis di Raspberry Pi...';
    }

    if (deviceState == DeviceConnectionState.transferring) {
      return 'Mentransfer Data...';
    }

    if (_isPrepared) return 'Alat Siap — Siap Dipindai';

    return 'Probe Terhubung';
  }

  String _subText(
    DeviceConnectionState deviceState,
    bool isScanning,
    ScanProgress? p,
  ) {
    if (deviceState == DeviceConnectionState.error) {
      return _lastError ?? 'Alat melaporkan kesalahan. Coba lagi.';
    }

    if (isScanning && p != null) return p.label;

    if (deviceState == DeviceConnectionState.capturing) {
      return 'Kamera mengambil foto lesi. Model CNN sedang melakukan klasifikasi...';
    }

    if (deviceState == DeviceConnectionState.transferring) {
      return 'Mengirim citra terkompresi dan data ultrasonik via Bluetooth ...';
    }

    if (_isPrepared) {
      return 'Tekan Pindai Sekarang untuk memulai pemindaian dari HP.';
    }

    return 'Tekan "Siapkan Alat" untuk menyalakan iluminasi sesuai mode yang dipilih.';
  }
}

// HELPER WIDGETS

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF0A858C)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingRing extends StatefulWidget {
  final double size;
  final double opacity;

  const _PulsingRing({
    required this.size,
    required this.opacity,
  });

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: Tween<double>(
          begin: widget.opacity * 0.4,
          end: widget.opacity,
        ).evaluate(_ctrl),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF77DAD7).withOpacity(widget.opacity),
          ),
        ),
      ),
    );
  }
}