import 'package:shared_preferences/shared_preferences.dart';

/// Local "delete for me" — hides messages only on this device/account.
class HiddenMessageStore {
  HiddenMessageStore._();

  static String _key(int userId, String chatId) =>
      'hidden_msgs_${userId}_${chatId.trim()}';

  static Future<Set<String>> load(int userId, String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key(userId, chatId)) ?? const [];
    return list.toSet();
  }

  static Future<void> hide({
    required int userId,
    required String chatId,
    required String messageId,
  }) async {
    final id = messageId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _key(userId, chatId);
    final set = (prefs.getStringList(key) ?? <String>[]).toSet()..add(id);
    await prefs.setStringList(key, set.toList());
  }
}
