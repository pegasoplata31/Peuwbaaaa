import 'dart:math' as math;

enum HandSide { left, right }

class SensorFrame {
  final List<double> fingers;
  final double pitch;
  final double roll;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;
  final DateTime time;

  SensorFrame({
    required this.fingers,
    required this.pitch,
    required this.roll,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  static SensorFrame? fromCsv(String raw) {
    final parts = raw.trim().split(',');
    if (parts.length < 9) return null;
    final bits = parts[0].trim();
    if (!RegExp(r'^[01]{5}$').hasMatch(bits)) return null;

    final nums = <double>[];
    for (int i = 1; i < 9; i++) {
      final v = double.tryParse(parts[i].trim());
      if (v == null) return null;
      nums.add(v);
    }

    return SensorFrame(
      fingers: bits.split('').map((e) => double.parse(e)).toList(),
      pitch: nums[0],
      roll: nums[1],
      ax: nums[2],
      ay: nums[3],
      az: nums[4],
      gx: nums[5],
      gy: nums[6],
      gz: nums[7],
    );
  }

  List<double> normalizedVector() => [
    ...fingers,
    pitch / 180.0,
    roll / 180.0,
    ax / 20.0,
    ay / 20.0,
    az / 20.0,
    gx / 10.0,
    gy / 10.0,
    gz / 10.0,
  ];

  static SensorFrame average(List<SensorFrame> frames) {
    if (frames.isEmpty) {
      return SensorFrame(
        fingers: List.filled(5, 0),
        pitch: 0, roll: 0, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0,
      );
    }
    double avg(Iterable<double> xs) => xs.reduce((a,b)=>a+b) / xs.length;
    final fingerAvg = List<double>.generate(
      5,
      (i) => avg(frames.map((f) => f.fingers[i])) >= .5 ? 1 : 0,
    );
    return SensorFrame(
      fingers: fingerAvg,
      pitch: avg(frames.map((f) => f.pitch)),
      roll: avg(frames.map((f) => f.roll)),
      ax: avg(frames.map((f) => f.ax)),
      ay: avg(frames.map((f) => f.ay)),
      az: avg(frames.map((f) => f.az)),
      gx: avg(frames.map((f) => f.gx)),
      gy: avg(frames.map((f) => f.gy)),
      gz: avg(frames.map((f) => f.gz)),
    );
  }
}

class TrainingGesture {
  final String id;
  final Map<String, String> translations;
  final List<List<double>> samples;
  final bool isDynamic;
  final bool useLeft;
  final bool useRight;

  TrainingGesture({
    required this.id,
    required this.translations,
    required this.samples,
    this.isDynamic = false,
    this.useLeft = true,
    this.useRight = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'translations': translations,
        'samples': samples,
        'isDynamic': isDynamic,
        'useLeft': useLeft,
        'useRight': useRight,
      };

  static TrainingGesture fromJson(Map<String, dynamic> json) => TrainingGesture(
        id: json['id'] as String,
        translations: Map<String, String>.from(json['translations'] as Map),
        samples: (json['samples'] as List)
            .map((e) => (e as List)
                .map((x) => (x as num).toDouble())
                .toList())
            .toList(),
        isDynamic: json['isDynamic'] as bool? ?? false,
        useLeft: json['useLeft'] as bool? ?? true,
        useRight: json['useRight'] as bool? ?? true,
      );
}

class RecognitionResult {
  final TrainingGesture gesture;
  final double distance;
  final double confidence;

  RecognitionResult(this.gesture, this.distance, this.confidence);
}

class GestureMath {
  static double vectorDistance(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return double.infinity;
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final delta = a[i] - b[i];
      sum += delta * delta;
    }
    return math.sqrt(sum / a.length);
  }

  static RecognitionResult? recognize(
    List<double> vector,
    List<TrainingGesture> gestures, {
    double threshold = 0.42,
    int k = 3,
  }) {
    RecognitionResult? best;

    for (final gesture in gestures) {
      if (gesture.samples.isEmpty) continue;

      final distances = gesture.samples
          .where((sample) => sample.length == vector.length)
          .map((sample) => vectorDistance(vector, sample))
          .toList()
        ..sort();

      if (distances.isEmpty) continue;

      final neighbors = distances.take(math.min(k, distances.length)).toList();
      final mean = neighbors.reduce((a, b) => a + b) / neighbors.length;
      final score =
          (1.0 - mean / threshold).clamp(0.0, 1.0).toDouble();

      if (best == null || mean < best.distance) {
        best = RecognitionResult(gesture, mean, score);
      }
    }

    if (best == null || best.distance > threshold) return null;
    return best;
  }
}
