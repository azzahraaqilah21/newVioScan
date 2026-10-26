import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_provider.dart';
import '../providers/auth_provider.dart';
import '../services/device_service.dart';
import '../models/screening_model.dart';

class HardwareConnectionScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;

  const HardwareConnectionScreen({
    super.key,
    required this.navigate,
  });

  @override
  ConsumerState<HardwareConnectionScreen> createState() =>
      _HardwareConnectionScreenState();
}

class _HardwareConnectionScreenState
    extends ConsumerState<HardwareConnectionScreen> {
  bool _useSimulation = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final state = ref.read(deviceStatusProvider);

      if (state != DeviceConnectionState.connected &&
          state != DeviceConnectionState.capturing &&
          state != DeviceConnectionState.transferring &&
          state != DeviceConnectionState.done) {
        ref.read(deviceStatusProvider.notifier).startScan();
      }
    });

    Future.microtask(() {
      if (!mounted) return;

      ref.listenManual<ScreeningModel?>(
        latestHardwareResultProvider,
        (previous, next) {
          if (next != null && mounted) {
            widget.navigate('result');
          }
        },
      );
    });
  }

  Future<void> _connectToDevice() async {
    await ref.read(deviceStatusProvider.notifier).connect();

    if (!mounted) return;

    final state = ref.read(deviceStatusProvider);

    if (state == DeviceConnectionState.connected) {
      widget.navigate('waiting_scan');
    }
  }

  Future<void> _disconnect() async {
    await ref.read(deviceStatusProvider.notifier).disconnect();
  }

  void _rescan() {
    ref.read(deviceStatusProvider.notifier).startScan();
  }

  Future<void> _logout() async {
    await ref.read(deviceStatusProvider.notifier).disconnect();
    await ref.read(authServiceProvider).signOut();

    if (mounted) {
      widget.navigate('login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(deviceStatusProvider);
    final probeAsync = ref.watch(deviceScanResultsProvider);
    final userAsync = ref.watch(currentUserProvider);

    final isConnected =
        connState == DeviceConnectionState.connected ||
        connState == DeviceConnectionState.capturing ||
        connState == DeviceConnectionState.transferring ||
        connState == DeviceConnectionState.done;

    final connectedDevice = ref.watch(
      deviceServiceProvider.select((service) => service.connectedDevice),
    );

    final displayName = userAsync.when(
      data: (user) => user?.displayName ?? 'VioScan User',
      loading: () => '...',
      error: (_, __) => 'VioScan User',
    );

    final email = userAsync.when(
      data: (user) => user?.email ?? '',
      loading: () => '',
      error: (_, __) => '',
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        ref.read(deviceStatusProvider.notifier).stopScan();
        widget.navigate('dashboard');
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Koneksi Bluetooth BC-Care',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              ref.read(deviceStatusProvider.notifier).stopScan();
              widget.navigate('dashboard');
            },
          ),
          actions: [
            if (!isConnected)
              IconButton(
                icon: connState == DeviceConnectionState.scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0A858C),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Cari perangkat Bluetooth',
                onPressed:
                    connState == DeviceConnectionState.scanning
                        ? null
                        : _rescan,
              ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Keluar Akun',
              onPressed: _logout,
            ),
          ],
        ),
        body: Column(
          children: [
            // Informasi pengguna
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              color: const Color(0xFFF0FAFA),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A858C).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF0A858C),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A858C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF0A858C).withOpacity(0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          size: 12,
                          color: Color(0xFF0A858C),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Terautentikasi',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0A858C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Status Bluetooth
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE6F7F7), Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: (isConnected
                              ? const Color(0xFF059669)
                              : const Color(0xFF0A858C))
                          .withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isConnected
                          ? Icons.bluetooth_connected_rounded
                          : connState == DeviceConnectionState.scanning ||
                                  connState ==
                                      DeviceConnectionState.connecting
                              ? Icons.bluetooth_searching_rounded
                              : Icons.bluetooth_rounded,
                      size: 36,
                      color: isConnected
                          ? const Color(0xFF059669)
                          : const Color(0xFF0A858C),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isConnected
                        ? 'Terhubung ke ${connectedDevice?.name ?? "BC-Care"}'
                        : connState == DeviceConnectionState.scanning
                            ? 'Mencari perangkat Bluetooth...'
                            : connState ==
                                    DeviceConnectionState.connecting
                                ? 'Menghubungkan melalui Bluetooth...'
                                : 'Hubungkan Raspberry Pi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isConnected
                          ? const Color(0xFF059669)
                          : const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isConnected
                        ? 'Bluetooth Classic aktif. Perangkat siap digunakan untuk pemindaian.'
                        : 'Gunakan Bluetooth Classic untuk menghubungkan HP ke Raspberry Pi. Wi-Fi tidak diperlukan.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (isConnected) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                widget.navigate('waiting_scan'),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text(
                              'Lanjut Pemindaian',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(
                            Icons.bluetooth_disabled_rounded,
                            size: 16,
                            color: Color(0xFFDC2626),
                          ),
                          label: const Text(
                            'Putus',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFFDC2626),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          _useSimulation = !_useSimulation;
                        });

                        ref
                            .read(deviceStatusProvider.notifier)
                            .setSimulationMode(_useSimulation);

                        _rescan();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _useSimulation
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _useSimulation
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _useSimulation
                                  ? Icons.developer_mode_rounded
                                  : Icons.sensors_rounded,
                              size: 15,
                              color: _useSimulation
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _useSimulation
                                  ? 'Mode Simulator Aktif'
                                  : 'Gunakan Mode Simulator (Uji Tanpa Alat)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _useSimulation
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF4B5563),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Daftar perangkat Bluetooth yang sudah dipasangkan
            if (!isConnected)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: probeAsync.when(
                      data: (devices) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              devices.isNotEmpty
                                  ? Icons.bluetooth_connected_rounded
                                  : Icons.bluetooth_searching_rounded,
                              size: 48,
                              color: devices.isNotEmpty
                                  ? const Color(0xFF0A858C)
                                  : const Color(0xFF9CA3AF),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              devices.isNotEmpty
                                  ? 'Perangkat Bluetooth ditemukan:'
                                  : 'Belum ada perangkat Bluetooth yang ditemukan.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),

                            if (devices.isNotEmpty)
                              ...devices.map(
                                (device) => Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FAFA),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFB9E4E4),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.bluetooth_rounded,
                                        color: Color(0xFF0A858C),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              device.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1F2937),
                                              ),
                                            ),
                                            Text(
                                              device.id,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: connState ==
                                        DeviceConnectionState.connecting
                                    ? null
                                    : _connectToDevice,
                                icon: const Icon(
                                  Icons.bluetooth_connected_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Hubungkan via Bluetooth',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0A858C),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Pastikan Raspberry Pi sudah dinyalakan dan dipasangkan melalui pengaturan Bluetooth HP.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _rescan,
                              icon: const Icon(
                                Icons.refresh_rounded,
                                size: 16,
                              ),
                              label: const Text('Cari Bluetooth Lagi'),
                            ),
                          ],
                        );
                      },
                      loading: () => const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Color(0xFF0A858C),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Memeriksa perangkat Bluetooth...',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      error: (err, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bluetooth_disabled_rounded,
                            size: 48,
                            color: Color(0xFFEF4444),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Bluetooth tidak dapat diakses.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Aktifkan Bluetooth HP dan izinkan aplikasi mengakses perangkat Bluetooth.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _rescan,
                            icon: const Icon(
                              Icons.refresh_rounded,
                              size: 16,
                            ),
                            label: const Text('Coba Lagi'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0A858C),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Tampilan ketika sudah terhubung
            if (isConnected)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF059669),
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Perangkat Siap',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        connectedDevice?.name ?? 'BC-Care UV-Scan Pro',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bluetooth_connected_rounded,
                              size: 14,
                              color: Color(0xFF059669),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Bluetooth Aktif',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}