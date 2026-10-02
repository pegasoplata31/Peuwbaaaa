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

  bool get leftConnected => leftDevice?.isConnected ?? false;
  bool get rightConnected => rightDevice?.isConnected ?? false;

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
    } else {
      rightDevice = device;
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

    await target.setNotifyValue(true);
    _valueSubs[device.remoteId.str]?.cancel();
    _valueSubs[device.remoteId.str] = target.onValueReceived.listen((bytes) {
      final raw = utf8.decode(bytes, allowMalformed: true).trim();
      _parse(raw, side);
    });

    status = 'Conectado: ${device.platformName}';
    notifyListeners();
  }

  Future<void> connectScanResult(ScanResult r, HandSide side) =>
      connectDevice(r.device, side);

  void _parse(String raw, HandSide sourceSide) {
    if (raw.isEmpty) return;

    // El firmware antiguo/procesado puede mandar "VOICE: GRACIAS".
    if (raw.toUpperCase().startsWith('VOICE:')) {
      final word = raw.substring(raw.indexOf(':') + 1).trim();
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
