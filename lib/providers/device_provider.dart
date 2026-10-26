import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/device_service.dart';
import '../models/screening_model.dart';

/// Singleton DeviceService untuk komunikasi Bluetooth Classic SPP.
/// Nama provider dipertahankan agar tidak mengubah layar konsumen.
final deviceServiceProvider = Provider<DeviceService>((ref) {
  final service = DeviceService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream daftar perangkat Bluetooth yang sudah dipasangkan.
final deviceScanResultsProvider = StreamProvider<List<DeviceInfo>>((ref) {
  return ref.watch(deviceServiceProvider).scanResults;
});

/// Stream kemajuan pemindaian dari Raspberry Pi.
final scanProgressProvider = StreamProvider<ScanProgress>((ref) {
  return ref.watch(deviceServiceProvider).progressStream;
});

// ── Koneksi Perangkat Bluetooth ──────────────────────────────────────────────

class DeviceStatusNotifier
    extends StateNotifier<DeviceConnectionState> {
  DeviceStatusNotifier(this._service)
      : super(_service.currentState) {
    _service.statusStream.listen((state) {
      if (mounted) {
        this.state = state;
      }
    });
  }

  final DeviceService _service;

  Future<void> startScan() => _service.startScan();

  void stopScan() => _service.stopScan();

  /// Hubungkan hanya ke perangkat Bluetooth yang ditemukan.
  /// Tidak menggunakan fallback alamat Wi-Fi.
  Future<void> connect() async {
    final device = _service.foundDevice;

    if (device == null) {
      throw StateError(
        'Perangkat Bluetooth belum ditemukan. '
        'Aktifkan Bluetooth dan tekan Cari Bluetooth Lagi.',
      );
    }

    await _service.connect(device);
  }

  Future<void> disconnect() => _service.disconnect();

  Future<void> sendPrepareScanCommand({
    String mode = 'uv',
  }) =>
      _service.sendPrepareScanCommand(mode: mode);

  Future<void> sendStartScanCommand({
    String mode = 'uv',
  }) =>
      _service.sendStartScanCommand(mode: mode);

  void setSimulationMode(bool enabled) {
    _service.setSimulationMode(enabled);
  }
}

final deviceStatusProvider =
    StateNotifierProvider<DeviceStatusNotifier,
        DeviceConnectionState>((ref) {
  return DeviceStatusNotifier(
    ref.watch(deviceServiceProvider),
  );
});

/// Dipertahankan agar kode layar lain tetap kompatibel.
/// Tidak digunakan sebagai tujuan koneksi Bluetooth.
DeviceInfo get defaultDevice => const DeviceInfo(
      id: '',
      name: 'BC-Care UV-Scan Pro',
      isBonded: true,
    );

// ── Captured Image ──────────────────────────────────────────────────────────

class CapturedImageNotifier extends StateNotifier<Uint8List?> {
  CapturedImageNotifier(DeviceService service) : super(null) {
    service.imageDataStream.listen((data) {
      if (mounted) {
        state = data;
      }
    });
  }

  void clear() => state = null;
}

final capturedImageProvider =
    StateNotifierProvider<CapturedImageNotifier, Uint8List?>((ref) {
  return CapturedImageNotifier(
    ref.watch(deviceServiceProvider),
  );
});

// ── Hardware Classification Result ──────────────────────────────────────────

class HardwareResultNotifier extends StateNotifier<ScreeningModel?> {
  HardwareResultNotifier(DeviceService service) : super(null) {
    service.resultStream.listen((screening) {
      if (mounted) {
        state = screening;
      }
    });
  }

  void setResult(ScreeningModel model) {
    state = model;
  }

  void clear() {
    state = null;
  }
}

final latestHardwareResultProvider =
    StateNotifierProvider<HardwareResultNotifier, ScreeningModel?>((ref) {
  return HardwareResultNotifier(
    ref.watch(deviceServiceProvider),
  );
});