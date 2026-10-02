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
    if (result == null || result.confidence < .35) {
      candidateId = null;
      candidateSince = null;
      return;
    }

    if (restVector != null && restVector!.length == v.length) {
      final restDistance = GestureMath.vectorDistance(v, restVector!);
      if (restDistance <= result.distance * 1.05) {
        candidateId = null;
        candidateSince = null;
        return;
      }
    }

    final now = DateTime.now();
    if (candidateId != result.gesture.id) {
      candidateId = result.gesture.id;
      candidateSince = now;
      return;
    }

    if (candidateSince != null &&
        now.difference(candidateSince!).inMilliseconds >= 300) {
      _acceptWord(result.gesture.id, result.confidence);
    }
  }

  void _acceptWord(String id, double conf) {
    if (recognized == id && conf < .98) return;
    recognized = id;
    confidence = conf;
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
    if (g != null) {
      final exact = g.translations[language];
      if (exact != null && exact.trim().isNotEmpty) return exact;
      if (language.startsWith('es-')) return g.translations['es'] ?? g.id;
      if (language.startsWith('zh-')) return g.translations['zh'] ?? g.id;
      return g.translations[language] ?? g.id;
    }
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
    await tts.setLanguage(locales[language] ?? 'es-PA');
    await tts.setSpeechRate(widget.speechRate);
    await tts.setVolume(widget.speechVolume);
    await tts.speak(translated);
  }

  Future<void> _captureRest() async {
    final v = _currentVector();
    if (v == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(
            'Conecta los guantes y mantén las manos relajadas.',
            'Connect the gloves and keep your hands relaxed.',
          )),
        ),
      );
      return;
    }

    restVector = List<double>.from(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('rest_vector', jsonEncode(restVector));

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t(
          'Postura de reposo guardada.',
          'Rest position saved.',
        )),
      ),
    );
  }

  Future<void> _showCalibrationWarning() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.back_hand_outlined),
        title: Text(_t('Calibración inicial', 'Initial calibration')),
        content: Text(
          _t(
            'Durante la calibración, relaja la mano de forma natural y luego forma un puño suavemente. No aprietes con fuerza, porque puede alterar los valores de flexión y reducir la precisión.',
            'During calibration, relax your hand naturally and then make a gentle fist. Do not squeeze hard because it can alter the flex values and reduce accuracy.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('Entendido', 'Got it')),
          ),
        ],
      ),
    );
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
      drawer: _settingsDrawer(),
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              width: 150,
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 8),
            const Text(
              'H&R',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
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
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.translate),
            label: _t('Traducir', 'Translate'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline),
            label: _t('Agregar', 'Add sign'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.terminal),
            label: _t('Terminal', 'Terminal'),
          ),
          const NavigationDestination(
            icon: Icon(Icons.bluetooth),
            label: 'BLE',
          ),
        ],
      ),
    );
  }

  Widget _settingsDrawer() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              _t('Configuración', 'Settings'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.darkMode,
              onChanged: widget.onDarkModeChanged,
              secondary: Icon(
                widget.darkMode ? Icons.dark_mode : Icons.light_mode,
              ),
              title: Text(_t('Modo oscuro', 'Dark mode')),
              subtitle: Text(_t(
                'Cambiar entre tema claro y oscuro',
                'Switch between light and dark theme',
              )),
            ),
            const Divider(),
            Text(
              _t('Idioma de la interfaz', 'Interface language'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'es', label: Text('Español')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {widget.uiLanguage},
              onSelectionChanged: (values) {
                if (values.isNotEmpty) {
                  widget.onUiLanguageChanged(values.first);
                }
              },
            ),
            const SizedBox(height: 22),
            Text(
              _t('Velocidad de voz', 'Speech speed'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Slider(
              value: widget.speechRate,
              min: 0.25,
              max: 0.70,
              divisions: 9,
              label: widget.speechRate.toStringAsFixed(2),
              onChanged: widget.onSpeechRateChanged,
            ),
            Text(
              _t('Volumen', 'Volume'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Slider(
              value: widget.speechVolume,
              min: 0,
              max: 1,
              divisions: 10,
              label: '${(widget.speechVolume * 100).round()}%',
              onChanged: widget.onSpeechVolumeChanged,
            ),
            const Divider(height: 30),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.self_improvement),
              title: Text(_t(
                'Guardar postura de reposo',
                'Save rest position',
              )),
              subtitle: Text(
                restVector == null
                    ? _t('Aún no configurada', 'Not configured')
                    : _t('Configurada', 'Configured'),
              ),
              onTap: _captureRest,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: Text(_t(
                'Ver aviso de calibración',
                'Show calibration notice',
              )),
              onTap: _showCalibrationWarning,
            ),
          ],
        ),
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
                DropdownButtonFormField<String>(
                  initialValue: language,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _t('Idioma de salida', 'Output language'),
                    prefixIcon: const Icon(Icons.language),
                  ),
                  items: languages.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => language = value);
                  },
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
            HandSide.left,
            ble.leftConnected,
            leftWindow.isNotEmpty,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statusCard(
            'Guante derecho',
            HandSide.right,
            ble.rightConnected,
            rightWindow.isNotEmpty,
          ),
        ),
      ],
    );
  }

  Widget _statusCard(
    String title,
    HandSide side,
    bool connected,
    bool hasParsedData,
  ) {
    String subtitle;
    Color iconColor = Colors.grey;

    if (!connected) {
      subtitle = 'Desconectado';
    } else if (hasParsedData || ble.receivingValidData(side)) {
      subtitle = 'Datos válidos recibidos';
      iconColor = const Color(0xFF54E0D2);
    } else if (ble.receivingBytes(side)) {
      subtitle = 'Recibe bytes, pero formato no válido';
      iconColor = Colors.orange;
    } else {
      subtitle = 'Conectado · esperando datos';
      iconColor = const Color(0xFF8AA3C1);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: iconColor,
            ),
            const SizedBox(height: 9),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF91A6C0)),
            ),
            if (connected) ...[
              const SizedBox(height: 4),
              Text(
                'RX: ${ble.notificationCount(side)} · válidos: ${ble.validFrameCount(side)}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF7188A6)),
              ),
            ],
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
      uiLanguage: widget.uiLanguage,
      currentVector: _currentVector,
      currentLeft: () => leftWindow.isEmpty ? null : leftWindow.last,
      currentRight: () => rightWindow.isEmpty ? null : rightWindow.last,
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
  final String uiLanguage;
  final List<double>? Function() currentVector;
  final SensorFrame? Function() currentLeft;
  final SensorFrame? Function() currentRight;
  final Future<void> Function(TrainingGesture) onSave;
  final Future<void> Function(TrainingGesture) onDelete;

  const TrainingPanel({
    super.key,
    required this.gestures,
    required this.uiLanguage,
    required this.currentVector,
    required this.currentLeft,
    required this.currentRight,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<TrainingPanel> createState() => _TrainingPanelState();
}

class _TrainingPanelState extends State<TrainingPanel> {
  static const trainingLanguages = <String, String>{
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

  final name = TextEditingController();
  late final Map<String, TextEditingController> translations = {
    for (final code in trainingLanguages.keys) code: TextEditingController(),
  };

  final List<List<double>> samples = [];
  bool isDynamic = false;
  bool useLeft = true;
  bool useRight = true;
  bool countingDown = false;
  bool readyToComplete = false;
  int countdown = 0;
  String message = '';

  String _t(String es, String en) =>
      widget.uiLanguage == 'en' ? en : es;

  @override
  void initState() {
    super.initState();
    message = _t(
      'Escribe una palabra y selecciona el tipo de seña.',
      'Enter a word and choose the sign type.',
    );
  }

  @override
  void dispose() {
    name.dispose();
    for (final controller in translations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<double>? _selectedVector() {
    final vector = widget.currentVector();
    if (vector == null || vector.length < 26) return null;

    final filtered = List<double>.from(vector);
    if (!useLeft) {
      for (int i = 0; i < 13; i++) {
        filtered[i] = 0;
      }
    }
    if (!useRight) {
      for (int i = 13; i < 26; i++) {
        filtered[i] = 0;
      }
    }
    return filtered;
  }

  Future<void> _startTrial() async {
    if (name.text.trim().isEmpty) {
      setState(() {
        message = _t(
          'Primero escribe el nombre de la seña.',
          'Enter the sign name first.',
        );
      });
      return;
    }

    if (!useLeft && !useRight) {
      setState(() {
        message = _t(
          'Activa por lo menos un guante.',
          'Enable at least one glove.',
        );
      });
      return;
    }

    if (_selectedVector() == null) {
      setState(() {
        message = _t(
          'No hay datos recientes de los guantes.',
          'There is no recent glove data.',
        );
      });
      return;
    }

    setState(() {
      countingDown = true;
      readyToComplete = false;
      countdown = 2;
      message = _t(
        'Prepárate para realizar la seña.',
        'Get ready to perform the sign.',
      );
    });

    for (int value = 2; value >= 1; value--) {
      if (!mounted) return;
      setState(() => countdown = value);
      await SystemSound.play(SystemSoundType.click);
      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted) return;
    await SystemSound.play(SystemSoundType.click);
    setState(() {
      countdown = 0;
      countingDown = false;
      readyToComplete = true;
      message = _t(
        'Realiza la seña y pulsa “Completar”.',
        'Perform the sign and tap “Complete”.',
      );
    });
  }

  void _completeTrial() {
    if (!readyToComplete || samples.length >= 10) return;

    final vector = _selectedVector();
    if (vector == null) {
      setState(() {
        readyToComplete = false;
        message = _t(
          'Se perdieron los datos BLE. Intenta esta repetición otra vez.',
          'BLE data was lost. Try this repetition again.',
        );
      });
      return;
    }

    SystemSound.play(SystemSoundType.click);
    setState(() {
      samples.add(vector);
      readyToComplete = false;
      message = samples.length < 10
          ? _t(
              'Repetición ${samples.length}/10 guardada. Pulsa “Iniciar” para la siguiente.',
              'Repetition ${samples.length}/10 saved. Tap “Start” for the next one.',
            )
          : _t(
              '10/10 listas. Guarda la nueva seña.',
              '10/10 complete. Save the new sign.',
            );
    });
  }

  Future<void> _save() async {
    if (samples.length != 10 || name.text.trim().isEmpty) return;

    final id = name.text.trim();
    final map = <String, String>{};
    for (final entry in translations.entries) {
      final value = entry.value.text.trim();
      map[entry.key] = value.isEmpty ? id : value;
    }

    await widget.onSave(
      TrainingGesture(
        id: id,
        translations: map,
        samples: List<List<double>>.from(samples),
        isDynamic: isDynamic,
        useLeft: useLeft,
        useRight: useRight,
      ),
    );

    if (!mounted) return;
    setState(() {
      samples.clear();
      name.clear();
      for (final controller in translations.values) {
        controller.clear();
      }
      readyToComplete = false;
      message = _t(
        'Seña guardada correctamente.',
        'Sign saved successfully.',
      );
    });
  }

  void _reset() {
    setState(() {
      samples.clear();
      countingDown = false;
      readyToComplete = false;
      countdown = 0;
      message = _t('Registro reiniciado.', 'Recording reset.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        countingDown ? (2 - countdown) / 2.0 : samples.length / 10.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _t('Agregar una nueva seña', 'Add a new sign'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _t(
            'Cada seña se registra 10 veces. Antes de cada repetición hay una cuenta regresiva de 2 segundos.',
            'Each sign is recorded 10 times. Every repetition starts with a 2-second countdown.',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: name,
          decoration: InputDecoration(
            labelText: _t('Nombre de la seña', 'Sign name'),
            hintText: _t('Ej. Buenos días', 'Example: Good morning'),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(_t('Estática', 'Static')),
              selected: !isDynamic,
              onSelected: (_) => setState(() => isDynamic = false),
            ),
            ChoiceChip(
              label: Text(_t('Dinámica · beta', 'Dynamic · beta')),
              selected: isDynamic,
              onSelected: (_) => setState(() => isDynamic = true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isDynamic
              ? _t(
                  'Modo dinámico: se muestran los datos de movimiento en tiempo real. La comparación DTW se añadirá en una fase posterior.',
                  'Dynamic mode: motion data is shown in real time. DTW comparison will be added in a later phase.',
                )
              : _t(
                  'Modo estático: se priorizan los dedos, Pitch y Roll.',
                  'Static mode: fingers, Pitch and Roll are prioritized.',
                ),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: useLeft,
                onChanged: (value) =>
                    setState(() => useLeft = value ?? true),
                title: Text(_t('Izquierdo', 'Left')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: useRight,
                onChanged: (value) =>
                    setState(() => useRight = value ?? true),
                title: Text(_t('Derecho', 'Right')),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
        if (isDynamic) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _telemetryMini(
                  _t('Izquierda', 'Left'),
                  widget.currentLeft(),
                  useLeft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _telemetryMini(
                  _t('Derecha', 'Right'),
                  widget.currentRight(),
                  useRight,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Center(
          child: SizedBox(
            width: 118,
            height: 118,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 9,
                  ),
                ),
                Text(
                  countingDown
                      ? '$countdown'
                      : '${samples.length}/10',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: countingDown ||
                        readyToComplete ||
                        samples.length >= 10
                    ? null
                    : _startTrial,
                icon: const Icon(Icons.play_arrow),
                label: Text(_t('Iniciar', 'Start')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: readyToComplete ? _completeTrial : null,
                icon: const Icon(Icons.check),
                label: Text(_t('Completar', 'Complete')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: samples.isEmpty ? null : _reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(_t('Reiniciar registro', 'Reset recording')),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF38BEC6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(_t(
            'Traducciones de la seña',
            'Sign translations',
          )),
          subtitle: Text(_t(
            'Opcional. Si un campo queda vacío se usa el nombre original.',
            'Optional. Empty fields use the original sign name.',
          )),
          children: trainingLanguages.entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: translations[entry.key],
                    decoration: InputDecoration(labelText: entry.value),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: samples.length == 10 ? _save : null,
          icon: const Icon(Icons.save),
          label: Text(_t('Guardar nueva seña', 'Save new sign')),
        ),
        const SizedBox(height: 26),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          _t(
            'Señas disponibles (${widget.gestures.length})',
            'Available signs (${widget.gestures.length})',
          ),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (widget.gestures.isEmpty)
          Text(_t(
            'Todavía no hay señas guardadas.',
            'No saved signs yet.',
          )),
        ...widget.gestures.map(
          (gesture) => Card(
            child: ListTile(
              leading: Icon(
                gesture.isDynamic
                    ? Icons.waves
                    : Icons.pan_tool_outlined,
              ),
              title: Text(gesture.id),
              subtitle: Text(
                '${gesture.samples.length} ${_t('muestras', 'samples')} · '
                '${gesture.isDynamic ? _t('Dinámica', 'Dynamic') : _t('Estática', 'Static')}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => widget.onDelete(gesture),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _telemetryMini(
    String title,
    SensorFrame? frame,
    bool enabled,
  ) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: frame == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text('—'),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(frame.fingers.map((e) => e.round()).join()),
                    Text(
                      'P ${frame.pitch.toStringAsFixed(1)}° · '
                      'R ${frame.roll.toStringAsFixed(1)}°',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'A ${frame.ax.toStringAsFixed(1)} '
                      '${frame.ay.toStringAsFixed(1)} '
                      '${frame.az.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      'G ${frame.gx.toStringAsFixed(1)} '
                      '${frame.gy.toStringAsFixed(1)} '
                      '${frame.gz.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
