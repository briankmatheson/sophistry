// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const String kCookieName = 'sophistry_session';
const String kRunUuidCookie = 'sophistry_run_uuid';
const String kProgressCookie = 'sophistry_progress';

/// Read the session UUID from cookie
String? getSessionId() {
  return _readCookie(kCookieName);
}

/// Read the run UUID from cookie (to restore review on return visit)
String? getSavedRunUuid() {
  return _readCookie(kRunUuidCookie);
}

/// Save run UUID to cookie so we can restore on return
void saveRunUuid(String runUuid) {
  html.document.cookie =
      '$kRunUuidCookie=$runUuid; path=/; max-age=${365 * 24 * 60 * 60}; SameSite=Lax';
}

/// Clear run UUID cookie
void clearRunUuid() {
  html.document.cookie = '$kRunUuidCookie=; path=/; max-age=0';
  html.document.cookie = '$kProgressCookie=; path=/; max-age=0';
}

/// Save questions-answered count
void saveProgress(int count) {
  html.document.cookie =
      '$kProgressCookie=$count; path=/; max-age=${365 * 24 * 60 * 60}; SameSite=Lax';
}

/// Read questions-answered count
int getSavedProgress() {
  final val = _readCookie(kProgressCookie);
  if (val == null) return 0;
  return int.tryParse(val) ?? 0;
}

/// Reload the page (web only)
void reloadPage() {
  html.window.location.reload();
}

String? _readCookie(String name) {
  final cookies = html.document.cookie ?? '';
  for (final cookie in cookies.split(';')) {
    final parts = cookie.trim().split('=');
    if (parts.length == 2 && parts[0] == name) {
      return parts[1];
    }
  }
  return null;
}
