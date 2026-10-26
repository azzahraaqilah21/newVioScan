import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/screening_model.dart';

/// State koneksi transport hardware (Bluetooth Classic SPP).
enum DeviceConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  capturing,
  transferring,
  done,
  error,
}

class DeviceInfo {
  final String id;
  final String name;
  final bool isBonded;
  final bool isSimulated;

  const DeviceInfo({
    required this.id,
    required this.name,
    this.isBonded = false,
    this.isSimulated = false,
  });
}

/// Kemajuan tahap scan yang diterima dari Raspberry Pi.
class ScanProgress {
  final int step;
  final int total;
  final String label;
  final int percent;

  const ScanProgress({
    required this.step,
    required this.total,
    required this.label,
    required this.percent,
  });
}

/// Service komunikasi Bluetooth Classic SPP ke Raspberry Pi 4.
class DeviceService {
  // Streams
  final _statusController =
      StreamController<DeviceConnectionState>.broadcast();
  final _devicesController =
      StreamController<List<DeviceInfo>>.broadcast();
  final _imageDataController = StreamController<Uint8List>.broadcast();
  final _resultController =
      StreamController<ScreeningModel>.broadcast();
  final _progressController = StreamController<ScanProgress>.broadcast();
  final _preparedController = StreamController<bool>.broadcast();
  final _deviceInfoController =
      StreamController<Map<String, dynamic>?>.broadcast();

  /// Info asli alat (serial, suhu CPU, daya, kamera, model AI) dari
  /// 'pong' / 'device_info'. null = belum terhubung.
  Map<String, dynamic>? _deviceInfo;
  Map<String, dynamic>? get deviceInfo => _deviceInfo;
  Stream<Map<String, dynamic>?> get deviceInfoStream =>
      _deviceInfoController.stream;

  void _setDeviceInfo(Map<String, dynamic>? info) {
    if (_disposed) return;
    _deviceInfo = info;
    _deviceInfoController.add(info);
  }

  /// Minta info alat terbaru (dipakai halaman Perangkat).
  Future<void> requestDeviceInfo() async {
    if (_connection?.isConnected == true) {
      await sendCommand(jsonEncode({'command': 'GET_INFO'}));
    }
  }

  Stream<DeviceConnectionState> get statusStream =>
      _statusController.stream;
  Stream<List<DeviceInfo>> get scanResults =>
      _devicesController.stream;
  Stream<Uint8List> get imageDataStream =>
      _imageDataController.stream;
  Stream<ScreeningModel> get resultStream =>
      _resultController.stream;
  Stream<ScanProgress> get progressStream =>
      _progressController.stream;

  /// True ketika Raspberry Pi mengirim scan_ready.
  Stream<bool> get preparedStream => _preparedController.stream;

  // State
  DeviceConnectionState _currentState =
      DeviceConnectionState.disconnected;

  DeviceConnectionState get currentState => _currentState;

  BluetoothConnection? _connection;
  DeviceInfo? _connectedDevice;
  DeviceInfo? get connectedDevice => _connectedDevice;

  Timer? _scanTimeoutTimer;
  Timer? _prepareTimeoutTimer;

  // Menunggu balasan 'shutting_down' / 'error' setelah perintah SHUTDOWN.
  Completer<String?>? _shutdownCompleter;

  static const _scanTimeoutSeconds = 60;
  static const _prepareTimeoutSeconds = 15;

  String? _lastErrorMessage;
  String? get lastErrorMessage => _lastErrorMessage;

  String _lastWarningMessage = '';
  String get lastWarningMessage => _lastWarningMessage;

  bool _forceSimulation = false;
  bool get isSimulation => _forceSimulation;

  bool _isPrepared = false;
  bool get isPrepared => _isPrepared;

  String _preparedMode = 'uv';

  void setSimulationMode(bool enabled) {
    _forceSimulation = enabled;
  }

  List<int> _receiveTail = <int>[];
  bool _disposed = false;

  DeviceInfo? _discoveredDevice;

  DeviceInfo? get foundDevice => _discoveredDevice;

  /// Dipanggil saat user mengetuk perangkat di daftar.
  void selectDevice(DeviceInfo device) {
    _discoveredDevice = device;
  }

  void _updateStatus(DeviceConnectionState state) {
    if (_disposed) return;

    _currentState = state;
    _statusController.add(state);
  }

  void _setPrepared(bool value) {
    if (_disposed) return;

    _isPrepared = value;
    _preparedController.add(value);
  }

  // ------------------------------------------------------------
  // SCAN PERANGKAT BLUETOOTH
  // ------------------------------------------------------------

  Future<void> startScan() async {
    _discoveredDevice = null;
    _lastErrorMessage = null;

    _updateStatus(DeviceConnectionState.scanning);

    if (isSimulation) {
      await Future.delayed(const Duration(milliseconds: 900));

      _discoveredDevice = const DeviceInfo(
        id: 'BCC-001-SIM',
        name: 'BC-Care UV-Scan Pro (Simulator)',
        isBonded: true,
        isSimulated: true,
      );

      _devicesController.add([_discoveredDevice!]);
      _updateStatus(DeviceConnectionState.disconnected);
      return;
    }

    try {
      // Android 12+ : izin runtime wajib diminta sebelum akses Bluetooth.
      // Di Android <12 status ini 'granted' otomatis (tidak diblokir).
      // Lokasi WAJIB juga: plugin flutter_bluetooth_serial 0.4.0 menolak
      // getBondedDevices() ("no_permissions") jika izin lokasi belum
      // diberikan, di versi Android berapa pun.
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.locationWhenInUse,
      ].request();

      final connectStatus = statuses[Permission.bluetoothConnect];
      if (connectStatus != null && !connectStatus.isGranted) {
        throw Exception(
          'Izin "Perangkat sekitar" belum diberikan. Buka Pengaturan > '
          'Aplikasi > vioscan_flutter > Izin, lalu izinkan "Perangkat sekitar".',
        );
      }

      final locationStatus = statuses[Permission.locationWhenInUse];
      if (locationStatus != null && !locationStatus.isGranted) {
        throw Exception(
          'Izin Lokasi belum diberikan. Plugin Bluetooth membutuhkan izin '
          'Lokasi untuk membaca daftar perangkat yang dipasangkan. Buka '
          'Pengaturan > Aplikasi > vioscan_flutter > Izin > Lokasi.',
        );
      }

      final bluetooth = FlutterBluetoothSerial.instance;
      final enabled = await bluetooth.isEnabled;

      if (enabled != true) {
        final result = await bluetooth.requestEnable();

        if (result != true) {
          throw Exception(
            'Bluetooth HP belum aktif atau izin mengaktifkan Bluetooth ditolak.',
          );
        }
      }

      // Timeout: di beberapa HP callback izin plugin tidak pernah kembali
      // sehingga Future menggantung dan UI loading selamanya.
      final bondedDevices = await bluetooth
          .getBondedDevices()
          .timeout(const Duration(seconds: 10));

      final devices = bondedDevices.map((device) {
        final address = device.address;
        final deviceName = device.name?.trim();

        return DeviceInfo(
          id: address,
          name: (deviceName == null || deviceName.isEmpty)
              ? address
              : deviceName,
          isBonded: true,
        );
      }).toList();

      final bcCareDevices = devices.where((device) {
        final name = device.name.toLowerCase().replaceAll('-', '');
        return name.contains('bccare') || name.contains('bc care');
      }).toList();

      // Tampilkan SEMUA perangkat terpasang, perangkat BC-Care di atas.
      // Pilih otomatis hanya jika namanya cocok; selain itu user memilih
      // sendiri (nama Bluetooth Pi bawaan = hostname, mis. 'raspberrypi',
      // sehingga mengambil .first bisa nyasar ke TWS/smartwatch).
      final discoveredDevices = [
        ...bcCareDevices,
        ...devices.where((d) => !bcCareDevices.contains(d)),
      ];

      _devicesController.add(discoveredDevices);
      if (bcCareDevices.isNotEmpty) {
        _discoveredDevice = bcCareDevices.first;
      }

      // Pi belum ter-pair (pairing bisa gagal karena Pi tidak punya agent
      // untuk konfirmasi passkey) → cari lewat discovery. Koneksinya nanti
      // memakai socket insecure di plugin, jadi tidak perlu pairing.
      if (bcCareDevices.isEmpty) {
        await _discoverUnpairedBcCare(bluetooth, discoveredDevices);
      }

      if (discoveredDevices.isNotEmpty) {
        _updateStatus(DeviceConnectionState.disconnected);
      } else {
        _lastErrorMessage =
            'Perangkat BC-Care tidak ditemukan. Pastikan Raspberry Pi menyala '
            'dan berada dekat HP, lalu tekan Cari Bluetooth Lagi.';
        _updateStatus(DeviceConnectionState.error);
      }
    } catch (e) {
      debugPrint('[BT] Pencarian perangkat gagal: $e');

      _discoveredDevice = null;
      _devicesController.add([]);

      _lastErrorMessage = e is TimeoutException
          ? 'Daftar perangkat Bluetooth tidak merespons. Pastikan izin '
              'Lokasi & Perangkat sekitar diberikan, lalu coba lagi.'
          : e.toString().replaceFirst('Exception: ', '');

      _updateStatus(DeviceConnectionState.error);
    }
  }

  static const _discoveryTimeoutSeconds = 12;

  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;

  /// Discovery Bluetooth Classic untuk perangkat BC-Care yang BELUM di-pair.
  /// Hasil yang cocok ditambahkan ke [list] (di posisi teratas) dan dipilih
  /// otomatis. Selesai saat discovery berakhir atau timeout.
  Future<void> _discoverUnpairedBcCare(
    FlutterBluetoothSerial bluetooth,
    List<DeviceInfo> list,
  ) async {
    final done = Completer<void>();

    await _discoverySubscription?.cancel();
    _discoverySubscription = bluetooth.startDiscovery().listen(
      (result) {
        final name = result.device.name?.trim() ?? '';
        final normalized = name.toLowerCase().replaceAll('-', '');
        final isBcCare =
            normalized.contains('bccare') || normalized.contains('bc care');
        if (!isBcCare || list.any((d) => d.id == result.device.address)) {
          return;
        }

        final device = DeviceInfo(
          id: result.device.address,
          name: name,
          isBonded: result.device.isBonded,
        );
        list.insert(0, device);
        _discoveredDevice ??= device;
        if (!_disposed) _devicesController.add(List.of(list));
        debugPrint('[BT] Ditemukan via discovery: $name (${device.id})');
      },
      onError: (Object e) {
        debugPrint('[BT] Discovery gagal: $e');
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    await done.future.timeout(
      const Duration(seconds: _discoveryTimeoutSeconds),
      onTimeout: () {},
    );
    await _discoverySubscription?.cancel();
    _discoverySubscription = null;
  }

  void stopScan() {
    _discoverySubscription?.cancel();
    _discoverySubscription = null;
    if (_currentState == DeviceConnectionState.scanning) {
      _updateStatus(DeviceConnectionState.disconnected);
    }
  }

  // ------------------------------------------------------------
  // CONNECT BLUETOOTH
  // ------------------------------------------------------------

  Future<void> connect(DeviceInfo device) async {
    _updateStatus(DeviceConnectionState.connecting);
    _lastErrorMessage = null;

    if (device.isSimulated || isSimulation) {
      await Future.delayed(const Duration(seconds: 1));

      _connectedDevice = device;
      _updateStatus(DeviceConnectionState.connected);
      return;
    }

    try {
      await _closeConnection();

      final connection =
          await BluetoothConnection.toAddress(device.id)
              // 45 detik: koneksi ke Pi yang belum di-pair memicu
              // permintaan pairing di sisi Pi (timeout agent BlueZ ±30 dtk);
              // beri waktu orang di Pi menekan "Terima".
              .timeout(const Duration(seconds: 45));

      _connection = connection;
      _receiveTail = <int>[];
      _connectedDevice = device;

      final input = connection.input;

      if (input == null) {
        throw Exception('Stream penerimaan Bluetooth tidak tersedia.');
      }

      input.listen(
        _onDataReceived,
        onError: (Object error) {
          debugPrint('[BT] Kesalahan koneksi: $error');
          disconnect();
        },
        onDone: () {
          debugPrint('[BT] Koneksi ditutup oleh Raspberry Pi.');
          disconnect();
        },
        cancelOnError: true,
      );

      _updateStatus(DeviceConnectionState.connected);

      await sendCommand('{"command":"PING"}');

      debugPrint(
        '[BT] Terhubung ke ${device.name} (${device.id})',
      );
    } catch (e) {
      debugPrint('[BT] Gagal terhubung ke ${device.id}: $e');

      await _closeConnection();

      _connectedDevice = null;

      _lastErrorMessage =
          'Tidak dapat terhubung ke ${device.name} melalui Bluetooth. '
          'Pastikan Raspberry Pi menjalankan server Bluetooth SPP, '
          'sudah dipasangkan dengan HP, dan alamat perangkat benar.\n'
          'Detail: $e';

      _updateStatus(DeviceConnectionState.error);

      await Future.delayed(const Duration(seconds: 1));

      if (_currentState == DeviceConnectionState.error) {
        _updateStatus(DeviceConnectionState.disconnected);
      }
    }
  }

  // ------------------------------------------------------------
  // DISCONNECT
  // ------------------------------------------------------------

  Future<void> disconnect() async {
    _cancelScanTimeout();
    _cancelPrepareTimeout();
    _setPrepared(false);
    _completeShutdown('Koneksi terputus sebelum alat mengonfirmasi.');

    await _closeConnection();

    _connectedDevice = null;
    _receiveTail = <int>[];
    _setDeviceInfo(null);

    _updateStatus(DeviceConnectionState.disconnected);
  }

  Future<void> _closeConnection() async {
    final connection = _connection;
    _connection = null;

    if (connection != null) {
      try {
        await connection.close();
      } catch (e) {
        debugPrint('[BT] Penutupan koneksi: $e');
      }
    }
  }

  // ------------------------------------------------------------
  // SEND JSON COMMAND
  // ------------------------------------------------------------

  Future<void> sendCommand(String command) async {
    final connection = _connection;

    if (connection == null ||
        !connection.isConnected ||
        _disposed) {
      _lastErrorMessage =
          'Perintah tidak dikirim karena Bluetooth belum terhubung.';
      debugPrint('[BT-TX] $_lastErrorMessage');
      return;
    }

    try {
      final formatted =
          command.endsWith('\n') ? command : '$command\n';

      connection.output.add(utf8.encode(formatted));
      await connection.output.allSent;

      debugPrint('[BT-TX] $command');
    } catch (e) {
      debugPrint('[BT-TX] Gagal mengirim perintah: $e');
      _lastErrorMessage = 'Gagal mengirim data melalui Bluetooth: $e';
      _updateStatus(DeviceConnectionState.error);
    }
  }

  // ------------------------------------------------------------
  // PREPARE SCAN
  // ------------------------------------------------------------

  Future<void> sendPrepareScanCommand({
    String mode = 'uv',
  }) async {
    if (_currentState != DeviceConnectionState.connected &&
        _currentState != DeviceConnectionState.done) {
      _lastErrorMessage = 'Hubungkan perangkat sebelum menyiapkan alat.';
      debugPrint('[BT] PREPARE_SCAN dibatalkan: status belum connected.');
      return;
    }

    if (mode != 'uv' && mode != 'white') {
      _lastErrorMessage = 'Mode pemindaian tidak valid: $mode';
      return;
    }

    _lastErrorMessage = null;
    _preparedMode = mode;
    _setPrepared(false);
    _cancelPrepareTimeout();

    if (_connection != null) {
      final cmd = jsonEncode({
        'command': 'PREPARE_SCAN',
        'mode': mode,
      });

      await sendCommand(cmd);

      if (_currentState == DeviceConnectionState.error) return;

      _prepareTimeoutTimer = Timer(
        const Duration(seconds: _prepareTimeoutSeconds),
        () {
          if (!_isPrepared && !_disposed) {
            _lastErrorMessage =
                'Raspberry Pi belum mengonfirmasi alat siap dalam '
                '$_prepareTimeoutSeconds detik.';
            debugPrint('[BT] Timeout menunggu scan_ready.');
            _updateStatus(DeviceConnectionState.connected);
          }
        },
      );

      return;
    }

    // Simulasi
    await Future.delayed(const Duration(milliseconds: 400));
    _setPrepared(true);
    _updateStatus(DeviceConnectionState.connected);
  }

  // ------------------------------------------------------------
  // SHUTDOWN (matikan Raspberry Pi)
  // ------------------------------------------------------------

  /// Minta Raspberry Pi mematikan diri (setara tahan tombol fisik 8 detik).
  /// Return null jika Pi mengonfirmasi 'shutting_down', atau pesan error.
  Future<String?> sendShutdownCommand() async {
    if (_currentState != DeviceConnectionState.connected &&
        _currentState != DeviceConnectionState.done) {
      return 'Alat belum terhubung atau sedang memindai.';
    }

    // Simulasi: tidak ada alat sungguhan yang perlu dimatikan.
    if (_connection == null) {
      await disconnect();
      return null;
    }

    final completer = Completer<String?>();
    _shutdownCompleter = completer;

    await sendCommand(jsonEncode({'command': 'SHUTDOWN'}));
    if (_currentState == DeviceConnectionState.error) {
      _completeShutdown(
        _lastErrorMessage ?? 'Gagal mengirim perintah ke alat.',
      );
    }

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _shutdownCompleter = null;
        return 'Alat tidak mengonfirmasi perintah mematikan.';
      },
    );
  }

  void _completeShutdown(String? error) {
    final completer = _shutdownCompleter;
    _shutdownCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(error);
    }
  }

  // ------------------------------------------------------------
  // START SCAN
  // ------------------------------------------------------------

  Future<void> sendStartScanCommand({
    String mode = 'uv',
  }) async {
    if (_currentState != DeviceConnectionState.connected &&
        _currentState != DeviceConnectionState.done) {
      _lastErrorMessage = 'Perangkat belum siap untuk memindai.';
      return;
    }

    if (!_isPrepared && _connection != null) {
      _lastErrorMessage =
          'Alat belum dikonfirmasi siap. Tekan Siapkan Alat terlebih dahulu.';
      debugPrint('[BT] START_SCAN ditolak: alat belum siap.');
      return;
    }

    if (mode != _preparedMode && _connection != null) {
      _lastErrorMessage =
          'Mode berubah. Siapkan alat kembali untuk mode $mode.';
      _setPrepared(false);
      return;
    }

    _cancelPrepareTimeout();
    _updateStatus(DeviceConnectionState.capturing);

    if (_connection != null) {
      final cmd = jsonEncode({
        'command': 'START_SCAN',
        'mode': mode,
      });

      await sendCommand(cmd);

      if (_currentState == DeviceConnectionState.error) return;

      _setPrepared(false);
      _startScanTimeout();
      return;
    }

    // Simulasi
    final steps = [
      'Menyalakan iluminasi & menghangatkan kamera...',
      'Mengambil foto lesi kulit...',
      'Menjalankan model CNN (EfficientNetB3)...',
      'Menyusun hasil & mengirim ke Android...',
    ];

    for (int i = 0; i < steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 700));

      if (_disposed) return;

      _progressController.add(
        ScanProgress(
          step: i + 1,
          total: steps.length,
          label: steps[i],
          percent: ((i + 1) / steps.length * 100).round(),
        ),
      );

      if (i == 2) {
        _updateStatus(DeviceConnectionState.transferring);
      }
    }

    await Future.delayed(const Duration(milliseconds: 600));

    if (_disposed) return;

    final demoModel = ScreeningModel.demo(
      userId: 'offline_local_user',
      lesionLocation: 'Dahi Kanan (Lesi 4mm)',
      riskLevel: 'high',
    );

    _resultController.add(demoModel);
    _setPrepared(false);
    _updateStatus(DeviceConnectionState.done);
  }

  // ------------------------------------------------------------
  // TIMEOUT
  // ------------------------------------------------------------

  void _startScanTimeout() {
    _cancelScanTimeout();

    _scanTimeoutTimer = Timer(
      const Duration(seconds: _scanTimeoutSeconds),
      () {
        if (_currentState == DeviceConnectionState.capturing ||
            _currentState == DeviceConnectionState.transferring) {
          debugPrint(
            '[BT] Timeout $_scanTimeoutSeconds detik '
            '- tidak ada respons dari Raspberry Pi.',
          );

          _lastErrorMessage =
              'Tidak ada respons dari Raspberry Pi dalam '
              '$_scanTimeoutSeconds detik. Periksa koneksi Bluetooth '
              'dan status perangkat.';

          _updateStatus(DeviceConnectionState.connected);
        }
      },
    );
  }

  void _cancelScanTimeout() {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
  }

  void _cancelPrepareTimeout() {
    _prepareTimeoutTimer?.cancel();
    _prepareTimeoutTimer = null;
  }

  // ------------------------------------------------------------
  // RECEIVE JSON + NEWLINE
  // ------------------------------------------------------------

  void _onDataReceived(Uint8List data) {
    final pending = <int>[];
    pending.addAll(_receiveTail);

    for (final byte in data) {
      if (byte == 0x0A) {
        if (pending.isNotEmpty) {
          final line = utf8
              .decode(pending, allowMalformed: true)
              .trim();

          if (line.isNotEmpty) {
            _handleJsonLine(line);
          }

          pending.clear();
        }
      } else {
        pending.add(byte);
      }
    }

    _receiveTail = pending;
  }

  void _handleJsonLine(String line) {
    try {
      final Map<String, dynamic> json = jsonDecode(line);
      final type = json['type'] as String?;

      debugPrint('[BT-RX] type=$type');

      switch (type) {
        case 'pong':
          debugPrint(
            '[BT-RX] Raspberry Pi siap: ${json['device']}',
          );
          if (json['info'] is Map) {
            _setDeviceInfo(Map<String, dynamic>.from(json['info'] as Map));
          }
          break;

        case 'device_info':
          if (json['info'] is Map) {
            _setDeviceInfo(Map<String, dynamic>.from(json['info'] as Map));
          }
          break;

        case 'error':
          _cancelScanTimeout();
          _cancelPrepareTimeout();
          _setPrepared(false);

          final errMsg =
              json['msg'] as String? ??
              'Terjadi kesalahan pada alat.';

          _lastErrorMessage = errMsg;
          _completeShutdown(errMsg);
          _updateStatus(DeviceConnectionState.error);

          debugPrint('[BT-RX] Error dari Raspberry Pi: $errMsg');

          Future.delayed(const Duration(seconds: 2), () {
            if (!_disposed &&
                _currentState == DeviceConnectionState.error) {
              _updateStatus(DeviceConnectionState.connected);
            }
          });
          break;

        case 'scan_started':
          _cancelPrepareTimeout();
          _setPrepared(false);
          _updateStatus(DeviceConnectionState.capturing);
          break;

        case 'scan_ready':
          _cancelPrepareTimeout();

          final receivedMode = json['mode'] as String? ?? _preparedMode;

          if (receivedMode != 'uv' && receivedMode != 'white') {
            _lastErrorMessage =
                'Raspberry Pi mengirim mode kesiapan yang tidak valid.';
            _setPrepared(false);
            _updateStatus(DeviceConnectionState.connected);
            break;
          }

          _preparedMode = receivedMode;
          _lastErrorMessage = null;
          _setPrepared(true);
          _updateStatus(DeviceConnectionState.connected);

          debugPrint(
            '[BT-RX] Alat siap (mode: $receivedMode)',
          );
          break;

        case 'scan_progress':
          _cancelScanTimeout();

          if (_currentState != DeviceConnectionState.capturing &&
              _currentState != DeviceConnectionState.transferring) {
            _updateStatus(DeviceConnectionState.capturing);
          }

          _progressController.add(
            ScanProgress(
              step: (json['step'] as num?)?.toInt() ?? 1,
              total: (json['total'] as num?)?.toInt() ?? 4,
              label: json['label'] as String? ?? '',
              percent: (json['percent'] as num?)?.toInt() ?? 0,
            ),
          );
          break;

        case 'classification_result':
          _cancelScanTimeout();
          _cancelPrepareTimeout();

          _updateStatus(DeviceConnectionState.transferring);

          final screening = ScreeningModel.fromDeviceJson(
            json,
            userId: 'pending_save',
            lesionLocation: 'Lesi Kulit',
          );

          if (screening.rawImageBytes != null) {
            _imageDataController.add(screening.rawImageBytes!);
          }

          _resultController.add(screening);
          _setPrepared(false);
          _updateStatus(DeviceConnectionState.done);

          debugPrint(
            '[BT-RX] Hasil: ${screening.prediction} '
            '(${screening.confidence.toStringAsFixed(1)}%)',
          );
          break;

        case 'shutting_down':
          debugPrint('[BT-RX] Raspberry Pi sedang dimatikan.');
          _completeShutdown(null);
          break;

        case 'scan_warning':
          _lastWarningMessage = json['msg'] as String? ?? '';

          debugPrint(
            '[BT-RX] Warning dari Raspberry Pi: '
            '$_lastWarningMessage',
          );
          break;

        case 'all_results':
          final count = (json['count'] as num?)?.toInt() ?? 0;
          debugPrint('[BT-RX] Riwayat: $count hasil');
          break;

        default:
          debugPrint('[BT-RX] Tipe tidak dikenal: $type');
      }
    } catch (e) {
      debugPrint('[BT-RX] Parse error: $e\nData: $line');
    }
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  void dispose() {
    _disposed = true;
    _cancelScanTimeout();
    _cancelPrepareTimeout();

    disconnect();

    _statusController.close();
    _devicesController.close();
    _imageDataController.close();
    _resultController.close();
    _progressController.close();
    _preparedController.close();
    _deviceInfoController.close();
  }
}