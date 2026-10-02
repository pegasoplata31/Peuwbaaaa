import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_manager.dart';
import 'models.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GuanteDeVozApp());
}

class GuanteDeVozApp extends StatefulWidget {
  const GuanteDeVozApp({super.key});

  @override
  State<GuanteDeVozApp> createState() => _GuanteDeVozAppState();
}

class _GuanteDeVozAppState extends State<GuanteDeVozApp> {
  bool darkMode = true;
  String uiLanguage = 'es';
  double speechRate = 0.45;
  double speechVolume = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      darkMode = prefs.getBool('dark_mode') ?? true;
      uiLanguage = prefs.getString('ui_language') ?? 'es';
      speechRate = prefs.getDouble('speech_rate') ?? 0.45;
      speechVolume = prefs.getDouble('speech_volume') ?? 1.0;
    });
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF07101F) : const Color(0xFFF4F8FD),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1DA1F2),
        brightness: brightness,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? const Color(0xFF0D1B31) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF0B172A) : const Color(0xFFEDF4FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Future<void> _setDarkMode(bool value) async {
    setState(() => darkMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
  }

  Future<void> _setUiLanguage(String value) async {
    setState(() => uiLanguage = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ui_language', value);
  }

  Future<void> _setSpeechRate(double value) async {
    setState(() => speechRate = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate', value);
  }

  Future<void> _setSpeechVolume(double value) async {
    setState(() => speechVolume = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_volume', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Beyond Words',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: HomeScreen(
        darkMode: darkMode,
        uiLanguage: uiLanguage,
        speechRate: speechRate,
        speechVolume: speechVolume,
        onDarkModeChanged: _setDarkMode,
        onUiLanguageChanged: _setUiLanguage,
        onSpeechRateChanged: _setSpeechRate,
        onSpeechVolumeChanged: _setSpeechVolume,
      ),
    );
  }
}

class LogEntry {
  final DateTime time;
  final String text;
  LogEntry(this.text) : time = DateTime.now();
}

class HomeScreen extends StatefulWidget {
  final bool darkMode;
  final String uiLanguage;
  final double speechRate;
  final double speechVolume;
  final ValueChanged<bool> onDarkModeChanged;
  final ValueChanged<String> onUiLanguageChanged;
  final ValueChanged<double> onSpeechRateChanged;
  final ValueChanged<double> onSpeechVolumeChanged;

  const HomeScreen({
    super.key,
    required this.darkMode,
    required this.uiLanguage,
    required this.speechRate,
    required this.speechVolume,
    required this.onDarkModeChanged,
    required this.onUiLanguageChanged,
    required this.onSpeechRateChanged,
    required this.onSpeechVolumeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ble = BleManager();
  final storage = GestureStorage();
  final tts = FlutterTts();

  final List<SensorFrame> leftWindow = [];
  final List<SensorFrame> rightWindow = [];
  final List<LogEntry> logs = [];
  List<TrainingGesture> gestures = [];
  List<double>? restVector;

  StreamSubscription<BlePacket>? packetSub;
  Timer? recognizeTimer;

  int tab = 0;
  String language = 'es-PA';
  String recognized = '—';
  double confidence = 0;
  String? candidateId;
  DateTime? candidateSince;

  String _t(String es, String en) => widget.uiLanguage == 'en' ? en : es;

  static const languages = <String, String>{
    'zh-yue': '中文（粤语）',
    'zh-cmn': '中文（普通话）',
    'es-PA': 'Español (Panamá)',
    'es-MX': 'Español (México)',
    'es-ES': 'Español (España)',
    'pt': 'Português',
    'en': 'English',
    'fr': 'Français',
    'de': 'Deutsch',
    'ar': 'العربية',
    'ru': 'Русский',
    'ja': '日本語',
    'ko': '한국어',
  };

  static const locales = <String, String>{
    'zh-yue': 'yue-HK',
    'zh-cmn': 'zh-CN',
    'es-PA': 'es-PA',
    'es-MX': 'es-MX',
    'es-ES': 'es-ES',
    'pt': 'pt-BR',
    'en': 'en-US',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'ar': 'ar-SA',
    'ru': 'ru-RU',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
  };

  @override
  void initState() {
    super.initState();
    _load();
    ble.addListener(_refresh);
    packetSub = ble.packets.listen(_onPacket);
    recognizeTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _recognize(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showCalibrationWarning();
    });
  }

  Future<void> _load() async {
    gestures = await storage.load();
    final prefs = await SharedPreferences.getInstance();
    final savedRest = prefs.getString('rest_vector');
    if (savedRest != null) {
      try {
        restVector = (jsonDecode(savedRest) as List)
            .map((e) => (e as num).toDouble())
            .toList();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _addFrame(List<SensorFrame> window, SensorFrame frame) {
    window.add(frame);
    while (window.length > 18) {
      window.removeAt(0);
    }
  }

  void _onPacket(BlePacket p) {
    logs.insert(0, LogEntry(p.raw));
    if (logs.length > 300) logs.removeLast();

    if (p.processedWord != null) {
      _acceptWord(p.processedWord!, 1.0);
      return;
    }

    if (p.left != null) _addFrame(leftWindow, p.left!);
    if (p.right != null) _addFrame(rightWindow, p.right!);
    if (p.frame != null && p.side == HandSide.left) {
      _addFrame(leftWindow, p.frame!);
    }
    if (p.frame != null && p.side == HandSide.right) {
      _addFrame(rightWindow, p.frame!);
    }
    if (mounted) setState(() {});
  }

  List<double>? _currentVector() {
    final now = DateTime.now();
    final left = leftWindow.where(
      (f) => now.difference(f.time).inMilliseconds < 700,
    ).toList();
    final right = rightWindow.where(
      (f) => now.difference(f.time).inMilliseconds < 700,
    ).toList();

    if (left.isEmpty && right.isEmpty) return null;

    final l = left.isEmpty
        ? List<double>.filled(13, 0)
        : SensorFrame.average(left).normalizedVector();
    final r = right.isEmpty
        ? List<double>.filled(13, 0)
        : SensorFrame.average(right).normalizedVector();
    return [...l, ...r];
  }

  void _recognize() {
    if (gestures.isEmpty) return;
    final v = _currentVector();
    if (v == null) return;
    final result = GestureMath.recognize(v, gestures);
    if (result != null && result.confidence >= .35) {
      _acceptWord(result.gesture.id, result.confidence);
    }
  }

  void _acceptWord(String id, double conf) {
    if (recognized == id && conf < .98) return;
    recognized = id;
    confidence = conf;
    statusMessage = 'Seña reconocida';
    if (mounted) setState(() {});
  }

  TrainingGesture? get currentGesture {
    for (final g in gestures) {
      if (g.id.toLowerCase() == recognized.toLowerCase()) return g;
    }
    return null;
  }

  String get translated {
    if (recognized == '—') return '—';
    final g = currentGesture;
    if (g != null) return g.translations[language] ?? g.id;
    return builtInTranslation(recognized, language);
  }

  String builtInTranslation(String word, String lang) {
    final key = word.trim().toUpperCase();
    const dict = {
      'HOLA': {'es':'Hola','en':'Hello','zh':'你好','fr':'Bonjour','pt':'Olá','de':'Hallo'},
      'GRACIAS': {'es':'Gracias','en':'Thank you','zh':'谢谢','fr':'Merci','pt':'Obrigado','de':'Danke'},
      'POR FAVOR': {'es':'Por favor','en':'Please','zh':'请','fr':"S'il vous plaît",'pt':'Por favor','de':'Bitte'},
      'AGUA': {'es':'Agua','en':'Water','zh':'水','fr':'Eau','pt':'Água','de':'Wasser'},
      'AYUDAME': {'es':'Ayúdame','en':'Help me','zh':'帮帮我','fr':'Aidez-moi','pt':'Ajude-me','de':'Hilf mir'},
      'AYÚDAME': {'es':'Ayúdame','en':'Help me','zh':'帮帮我','fr':'Aidez-moi','pt':'Ajude-me','de':'Hilf mir'},
      'COMIDA': {'es':'Comida','en':'Food','zh':'食物','fr':'Nourriture','pt':'Comida','de':'Essen'},
      'YO': {'es':'Yo','en':'I / Me','zh':'我','fr':'Moi','pt':'Eu','de':'Ich'},
      'TE QUIERO': {'es':'Te quiero','en':'I love you','zh':'我爱你','fr':"Je t'aime",'pt':'Eu te amo','de':'Ich liebe dich'},
      'OTRO': {'es':'Otro','en':'Other','zh':'其他','fr':'Autre','pt':'Outro','de':'Andere'},
      'SI': {'es':'Sí','en':'Yes','zh':'是','fr':'Oui','pt':'Sim','de':'Ja'},
      'NO': {'es':'No','en':'No','zh':'不','fr':'Non','pt':'Não','de':'Nein'},
    };
    return dict[key]?[lang] ?? word;
  }

  Future<void> _speak() async {
    if (translated == '—') return;
    await tts.setLanguage(locales[language] ?? 'es-ES');
    await tts.speak(translated);
  }

  @override
  void dispose() {
    ble.removeListener(_refresh);
    packetSub?.cancel();
    recognizeTimer?.cancel();
    ble.dispose();
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _translatePage(),
      _trainingPage(),
      _terminalPage(),
      _bluetoothPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF07101F),
        titleSpacing: 16,
        title: Image.asset('assets/logo.png', height: 42),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: _pill(
                ble.leftConnected && ble.rightConnected
                    ? '2/2 BLE'
                    : '${ble.leftConnected || ble.rightConnected ? 1 : 0}/2 BLE',
                ble.leftConnected && ble.rightConnected,
              ),
            ),
          )
        ],
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.translate), label: 'Traducir'),
          NavigationDestination(icon: Icon(Icons.model_training), label: 'Entrenar'),
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Terminal'),
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'BLE'),
        ],
      ),
    );
  }

  Widget _translatePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _connectionStrip(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'TRADUCCIÓN EN TIEMPO REAL',
                  style: TextStyle(
                    color: Color(0xFF54E0D2),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  translated,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  recognized == '—'
                      ? 'Esperando una seña...'
                      : 'Confianza ${(confidence * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF9FB3CC)),
                ),
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: languages.entries.map((e) {
                    final selected = language == e.key;
                    return ChoiceChip(
                      label: Text(e.value),
                      selected: selected,
                      onSelected: (_) => setState(() => language = e.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: translated == '—' ? null : _speak,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Reproducir voz'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sensorSummary(),
      ],
    );
  }

  Widget _connectionStrip() {
    return Row(
      children: [
        Expanded(
          child: _statusCard(
            'Guante izquierdo',
            ble.leftConnected,
            leftWindow.isNotEmpty ? 'Recibiendo datos' : 'Sin datos',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statusCard(
            'Guante derecho',
            ble.rightConnected,
            rightWindow.isNotEmpty ? 'Recibiendo datos' : 'Sin datos',
          ),
        ),
      ],
    );
  }

  Widget _statusCard(String title, bool connected, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: connected ? const Color(0xFF54E0D2) : Colors.grey,
            ),
            const SizedBox(height: 9),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              connected ? subtitle : 'Desconectado',
              style: const TextStyle(fontSize: 12, color: Color(0xFF91A6C0)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sensorSummary() {
    SensorFrame? l = leftWindow.isEmpty ? null : leftWindow.last;
    SensorFrame? r = rightWindow.isEmpty ? null : rightWindow.last;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Datos actuales',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('Izquierda: ${_brief(l)}'),
            const SizedBox(height: 7),
            Text('Derecha: ${_brief(r)}'),
            const SizedBox(height: 12),
            Text(
              gestures.isEmpty
                  ? 'Todavía no hay palabras entrenadas. La app también acepta mensajes procesados tipo VOICE: GRACIAS.'
                  : '${gestures.length} palabra(s) entrenada(s) localmente.',
              style: const TextStyle(color: Color(0xFF91A6C0), fontSize: 12),
            )
          ],
        ),
      ),
    );
  }

  String _brief(SensorFrame? f) {
    if (f == null) return '—';
    final bits = f.fingers.map((x) => x.round()).join();
    return '$bits · P ${f.pitch.toStringAsFixed(1)}° · R ${f.roll.toStringAsFixed(1)}°';
  }

  Widget _trainingPage() {
    return TrainingPanel(
      gestures: gestures,
      currentVector: _currentVector,
      onSave: (gesture) async {
        final index = gestures.indexWhere(
          (g) => g.id.toLowerCase() == gesture.id.toLowerCase(),
        );
        if (index >= 0) {
          gestures[index] = gesture;
        } else {
          gestures.add(gesture);
        }
        await storage.save(gestures);
        if (mounted) setState(() {});
      },
      onDelete: (g) async {
        gestures.remove(g);
        await storage.save(gestures);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _terminalPage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Terminal de datos BLE',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(logs.clear),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Limpiar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? const Center(child: Text('Aún no hay datos recibidos.'))
              : ListView.builder(
                  reverse: false,
                  padding: const EdgeInsets.all(12),
                  itemCount: logs.length,
                  itemBuilder: (_, i) {
                    final l = logs[i];
                    final t =
                        '${l.time.hour.toString().padLeft(2,'0')}:${l.time.minute.toString().padLeft(2,'0')}:${l.time.second.toString().padLeft(2,'0')}';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1526),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '[$t] ${l.text}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Color(0xFF9EE7D7),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _bluetoothPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Conexión BLE',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          ble.status,
          style: const TextStyle(color: Color(0xFF9FB3CC)),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: ble.scanning ? null : ble.scanAndAutoConnect,
          icon: ble.scanning
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bluetooth_searching),
          label: Text(ble.scanning ? 'Buscando...' : 'Buscar y conectar guantes'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: ble.leftConnected || ble.rightConnected
              ? ble.disconnectAll
              : null,
          icon: const Icon(Icons.link_off),
          label: const Text('Desconectar todo'),
        ),
        const SizedBox(height: 18),
        _connectionStrip(),
        const SizedBox(height: 20),
        const Text('Dispositivos encontrados',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...ble.scanResults.map((r) {
          final name = r.device.platformName.isEmpty
              ? (r.advertisementData.advName.isEmpty
                  ? 'BLE sin nombre'
                  : r.advertisementData.advName)
              : r.device.platformName;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(name),
              subtitle: Text('${r.device.remoteId} · RSSI ${r.rssi}'),
              trailing: PopupMenuButton<HandSide>(
                onSelected: (side) => ble.connectScanResult(r, side),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: HandSide.left,
                    child: Text('Conectar como izquierdo'),
                  ),
                  PopupMenuItem(
                    value: HandSide.right,
                    child: Text('Conectar como derecho'),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 18),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'La app busca SmartGlove_Left y SmartGlove_Right. Ambos pueden conectarse al mismo teléfono al mismo tiempo. '
              'Si usas el modo de un solo enlace, el guante transmisor puede enviar DUAL|<izquierda>|<derecha> o JSON con las claves left y right.',
              style: TextStyle(color: Color(0xFF9FB3CC)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, bool ok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: ok ? const Color(0xFF123A3A) : const Color(0xFF302B38),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: ok ? const Color(0xFF54E0D2) : const Color(0xFFC9B4D2),
          ),
        ),
      );
}

class TrainingPanel extends StatefulWidget {
  final List<TrainingGesture> gestures;
  final List<double>? Function() currentVector;
  final Future<void> Function(TrainingGesture) onSave;
  final Future<void> Function(TrainingGesture) onDelete;

  const TrainingPanel({
    super.key,
    required this.gestures,
    required this.currentVector,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<TrainingPanel> createState() => _TrainingPanelState();
}

class _TrainingPanelState extends State<TrainingPanel> {
  final name = TextEditingController();
  final translations = <String, TextEditingController>{
    'es': TextEditingController(),
    'en': TextEditingController(),
    'zh': TextEditingController(),
    'fr': TextEditingController(),
    'pt': TextEditingController(),
    'de': TextEditingController(),
  };
  final List<List<double>> samples = [];
  String message = 'Escribe una palabra y realiza la seña.';

  @override
  void dispose() {
    name.dispose();
    for (final c in translations.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _capture() {
    final v = widget.currentVector();
    if (v == null) {
      setState(() => message = 'No hay datos recientes de los guantes.');
      return;
    }
    if (name.text.trim().isEmpty) {
      setState(() => message = 'Primero escribe el nombre de la palabra.');
      return;
    }
    if (samples.length >= 10) return;
    setState(() {
      samples.add(List<double>.from(v));
      message = samples.length < 10
          ? 'Muestra ${samples.length}/10 guardada. Repite la seña y pulsa Listo.'
          : '10/10 muestras listas. Guarda la palabra.';
    });
  }

  Future<void> _save() async {
    if (samples.length != 10 || name.text.trim().isEmpty) return;
    final id = name.text.trim();
    final map = <String, String>{};
    for (final e in translations.entries) {
      map[e.key] = e.value.text.trim().isEmpty ? id : e.value.text.trim();
    }
    await widget.onSave(
      TrainingGesture(id: id, translations: map, samples: List.from(samples)),
    );
    setState(() {
      samples.clear();
      name.clear();
      for (final c in translations.values) c.clear();
      message = 'Palabra guardada. Puedes entrenar otra.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Agregar / entrenar palabra',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cada palabra se registra 10 veces. Después de realizar cada seña, pulsa “Listo”.',
          style: TextStyle(color: Color(0xFF9FB3CC)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Palabra / nombre de la seña',
            hintText: 'Ej. Buenos días',
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Traducciones de esta palabra (6 idiomas)'),
          subtitle: const Text(
            'Si dejas un campo vacío, se usará el nombre original.',
            style: TextStyle(fontSize: 12),
          ),
          children: [
            _langField('Español', translations['es']!),
            _langField('English', translations['en']!),
            _langField('中文', translations['zh']!),
            _langField('Français', translations['fr']!),
            _langField('Português', translations['pt']!),
            _langField('Deutsch', translations['de']!),
          ],
        ),
        const SizedBox(height: 14),
        LinearProgressIndicator(value: samples.length / 10),
        const SizedBox(height: 8),
        Text(
          '${samples.length}/10 grabaciones',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: samples.length < 10 ? _capture : null,
          icon: const Icon(Icons.check_circle),
          label: const Text('Listo — guardar esta prueba'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: samples.length == 10 ? _save : null,
          icon: const Icon(Icons.save),
          label: const Text('Guardar nueva palabra'),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF54E0D2)),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'Palabras entrenadas (${widget.gestures.length})',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (widget.gestures.isEmpty)
          const Text(
            'No hay palabras entrenadas todavía.',
            style: TextStyle(color: Color(0xFF9FB3CC)),
          ),
        ...widget.gestures.map((g) => Card(
              child: ListTile(
                title: Text(g.id),
                subtitle: Text('${g.samples.length} muestras'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => widget.onDelete(g),
                ),
              ),
            )),
      ],
    );
  }

  Widget _langField(String label, TextEditingController controller) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
