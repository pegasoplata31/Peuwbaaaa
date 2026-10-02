import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class GestureStorage {
  static const _key = 'trained_gestures_v1';

  Future<List<TrainingGesture>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => TrainingGesture.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> save(List<TrainingGesture> gestures) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(gestures.map((g) => g.toJson()).toList()),
    );
  }
}
