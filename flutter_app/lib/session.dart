import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

const String _kSessionId = 'sophistry_session';
const String _kRunUuid = 'sophistry_run_uuid';
const String _kProgress = 'sophistry_progress';
const String _kTestSetId = 'sophistry_test_set';

/// Cached prefs instance — call initSession() once at startup
SharedPreferences? _prefs;

/// Must be called once before any other session function (e.g. in main)
Future<void> initSession() async {
  _prefs = await SharedPreferences.getInstance();
}

SharedPreferences get _p {
  assert(_prefs != null, 'Call initSession() before using session functions');
  return _prefs!;
}

// ─── Session ────────────────────────────────────────────
String? getSessionId() => _p.getString(_kSessionId);

// ─── Run UUID ───────────────────────────────────────────
String? getSavedRunUuid() => _p.getString(_kRunUuid);

void saveRunUuid(String runUuid) => _p.setString(_kRunUuid, runUuid);

void clearRunUuid() {
  _p.remove(_kRunUuid);
  _p.remove(_kProgress);
}

// ─── Progress ───────────────────────────────────────────
void saveProgress(int count) => _p.setInt(_kProgress, count);

int getSavedProgress() => _p.getInt(_kProgress) ?? 0;

// ─── Test Set ───────────────────────────────────────────
void saveTestSetId(int id) => _p.setInt(_kTestSetId, id);

int? getSavedTestSetId() => _p.getInt(_kTestSetId);

// ─── Reload (web only, no-op on native) ─────────────────
void reloadPage() {
  // On native, the caller should handle navigation differently
  // Web: handled by session_web.dart conditional import if needed
}

// ─── Clear web caches (no-op on native) ─────────────────
void clearWebCaches() {
  // Web: handled by session_web.dart conditional import if needed
}
