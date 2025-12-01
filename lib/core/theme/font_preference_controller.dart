import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFontKey = 'app_font_key_v1';

class FontController extends StateNotifier<String> {
  FontController() : super('inter') {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kFontKey);
      if (v != null && v.isNotEmpty) state = v;
    } catch (_) {}
  }

  Future<void> set(String fontKey) async {
    state = fontKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kFontKey, fontKey);
    } catch (_) {}
  }
}

final fontProvider = StateNotifierProvider<FontController, String>((ref) => FontController());
