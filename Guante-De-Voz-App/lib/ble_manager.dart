import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'models.dart';

class BlePacket {
  final HandSide? side;
  final String raw;
  final SensorFrame? frame;
  final SensorFrame? left;
  final SensorFrame? right;
  final String? processedWord;

  BlePacket({
    required this.raw,
    this.side,
    this.frame,
    this.left,
    this.right,
    this.processedWord,
  });
}

class BleManager extends ChangeNotifier {
  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const characteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const leftName = 'SmartGlove_Left';
  static const rightName = 'SmartGlove_Right';

  BluetoothDevice? leftDevice;
  BluetoothDevice? rightDevice;
  bool scanning = false;
  String status = 'Listo para buscar guantes';

  final _packetController = StreamController<BlePacket>.broadcast();
  Stream<BlePacket> get packets => _packetController.stream;

  final List<ScanResult> scanResults = [];
  final Map<String, StreamSubscription<List<int>>> _valueSubs = {};
  final Map<String, StreamSubscription<BluetoothConnectionState>> _connSubs = {};

  DateTime? _leftLastRx;
  DateTime? _rightLastRx;
  DateTime? _leftLastValid;
  DateTime? _rightLastValid;
  int _leftNotifications = 0;
  int _rightNotifications = 0;
  int _leftValidFrames = 0;
  int _rightValidFrames = 0;

  bool get leftConnected => leftDevice?.isConnected ?? false;
  bool get rightConnected => rightDevice?.isConnected ?? false;

  int notificationCount(HandSide side) =>
      side == HandSide.left ? _leftNotifications : _rightNotifications;

  int validFrameCount(HandSide side) =>
      side == HandSide.left ? _leftValidFrames : _rightValidFrames;

  bool receivingBytes(HandSide side) {
    final last = side == HandSide.left ? _leftLastRx : _rightLastRx;
    return last != null &&
        DateTime.now().difference(last).inMilliseconds < 1800;
  }

  bool receivingValidData(HandSide side) {
    final last = side == HandSide.left ? _leftLastValid : _rightLastValid;
    return last != null &&
        DateTime.now().difference(last).inMilliseconds < 1800;
  }

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> scanAndAutoConnect() async {
    await requestPermissions();
    scanResults.clear();
    scanning = true;
    status = 'Buscando SmartGlove_Left y SmartGlove_Right...';
    notifyListeners();

    final sub = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        if (!scanResults.any((x) => x.device.remoteId == r.device.remoteId)) {
          scanResults.add(r);
          notifyListeners();
        }
        if (name == leftName && leftDevice == null) {
          await connectDevice(r.device, HandSide.left);
        } else if (name == rightName && rightDevice == null) {
          await connectDevice(r.device, HandSide.right);
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        withServices: [Guid(serviceUuid)],
      );
      await Future.delayed(const Duration(seconds: 8));
    } catch (_) {
      // A second scan may already be stopping; keep UI usable.
    } finally {
      await sub.cancel();
      scanning = false;
      status = 'Búsqueda finalizada';
      notifyListeners();
    }
  }

  Future<void> connectDevice(BluetoothDevice device, HandSide side) async {
    status = 'Conectando ${side == HandSide.left ? "izquierdo" : "derecho"}...';
    notifyListeners();

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );
    } catch (_) {
      if (!device.isConnected) rethrow;
    }

    if (side == HandSide.left) {
      leftDevice = device;
      _leftLastRx = null;
      _leftLastValid = null;
      _leftNotifications = 0;
      _leftValidFrames = 0;
    } else {
      rightDevice = device;
      _rightLastRx = null;
      _rightLastValid = null;
      _rightNotifications = 0;
      _rightValidFrames = 0;
    }

    _connSubs[device.remoteId.str]?.cancel();
    _connSubs[device.remoteId.str] = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        if (leftDevice?.remoteId == device.remoteId) leftDevice = null;
        if (rightDevice?.remoteId == device.remoteId) rightDevice = null;
        notifyListeners();
      }
    });

    final services = await device.discoverServices();
    BluetoothCharacteristic? target;
    for (final s in services) {
      if (s.uuid.str.toLowerCase() == serviceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid.str.toLowerCase() == characteristicUuid) {
            target = c;
          }
        }
      }
    }
    if (target == null) {
      throw Exception('No se encontró la característica BLE del guante.');
    }

    _valueSubs[device.remoteId.str]?.cancel();
    final subscription = target.onValueReceived.listen((bytes) {
      _markNotification(side);
      _handleNotification(bytes, side);
    });
    _valueSubs[device.remoteId.str] = subscription;
    device.cancelWhenDisconnected(subscription);

    await target.setNotifyValue(true);

    status = 'Conectado: ${device.platformName}';
    notifyListeners();
  }

  Future<void> connectScanResult(ScanResult r, HandSide side) =>
      connectDevice(r.device, side);

  void _markNotification(HandSide side) {
    final now = DateTime.now();
    if (side == HandSide.left) {
      _leftLastRx = now;
      _leftNotifications++;
    } else {
      _rightLastRx = now;
      _rightNotifications++;
    }
    notifyListeners();
  }

  void _markValid(HandSide side) {
    final now = DateTime.now();
    if (side == HandSide.left) {
      _leftLastValid = now;
      _leftValidFrames++;
    } else {
      _rightLastValid = now;
      _rightValidFrames++;
    }
    notifyListeners();
  }

  String _hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  bool _isPrintableAscii(List<int> bytes) {
    for (final byte in bytes) {
      final control = byte == 9 || byte == 10 || byte == 13;
      final printable = byte >= 32 && byte <= 126;
      if (!control && !printable) return false;
    }
    return true;
  }

  void _handleNotification(List<int> bytes, HandSide side) {
    if (bytes.isEmpty) return;

    if (!_isPrintableAscii(bytes)) {
      _packetController.add(BlePacket(
        raw: '[BINARIO ${bytes.length} B] HEX: ${_hex(bytes)}',
        side: side,
      ));
      return;
    }

    final raw = utf8.decode(bytes).trim();
    if (raw.isEmpty) return;
    _parse(raw, side);
  }

  void _parse(String raw, HandSide sourceSide) {
    if (raw.isEmpty) return;

    // El firmware antiguo/procesado puede mandar "VOICE: GRACIAS".
    if (raw.toUpperCase().startsWith('VOICE:')) {
      final word = raw.substring(raw.indexOf(':') + 1).trim();
      _markValid(sourceSide);
      _packetController.add(BlePacket(
        raw: raw,
        side: sourceSide,
        processedWord: word,
      ));
      return;
    }

    // Fallback de un solo guante que reenvía ambos:
    // DUAL|<payload izquierdo>|<payload derecho>
    if (raw.startsWith('DUAL|')) {
      final parts = raw.split('|');
      if (parts.length >= 3) {
        final l = SensorFrame.fromCsv(parts[1]);
        final r = SensorFrame.fromCsv(parts[2]);
        if (l != null || r != null) _markValid(sourceSide);
        _packetController.add(BlePacket(raw: raw, left: l, right: r));
        return;
      }
    }

    // También acepta JSON:
    // {"left":"10101,...","right":"01010,..."}
    if (raw.startsWith('{')) {
      try {
        final obj = jsonDecode(raw) as Map<String, dynamic>;
        final lraw = obj['left']?.toString();
        final rraw = obj['right']?.toString();
        final l = lraw == null ? null : SensorFrame.fromCsv(lraw);
        final r = rraw == null ? null : SensorFrame.fromCsv(rraw);
        if (l != null || r != null) {
          _markValid(sourceSide);
          _packetController.add(BlePacket(raw: raw, left: l, right: r));
          return;
        }
      } catch (_) {}
    }

    // Prefijos opcionales L:/R:
    String payload = raw;
    HandSide side = sourceSide;
    if (raw.startsWith('L:')) {
      side = HandSide.left;
      payload = raw.substring(2);
    } else if (raw.startsWith('R:')) {
      side = HandSide.right;
      payload = raw.substring(2);
    }

    final frame = SensorFrame.fromCsv(payload);
    if (frame != null) _markValid(side);
    _packetController.add(BlePacket(
      raw: raw,
      side: side,
      frame: frame,
    ));
  }

  Future<void> disconnectAll() async {
    for (final s in _valueSubs.values) {
      await s.cancel();
    }
    _valueSubs.clear();
    for (final d in [leftDevice, rightDevice]) {
      if (d != null && d.isConnected) {
        await d.disconnect();
      }
    }
    leftDevice = null;
    rightDevice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _valueSubs.values) {
      s.cancel();
    }
    for (final s in _connSubs.values) {
      s.cancel();
    }
    _packetController.close();
    super.dispose();
  }
}
