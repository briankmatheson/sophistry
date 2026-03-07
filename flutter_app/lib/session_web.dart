// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;

/// Clear browser caches (service worker caches + force reload)
void clearBrowserCaches() {
  try {
    // Delete all service worker caches
    js.context.callMethod('eval', ['''
      if ('caches' in window) {
        caches.keys().then(function(names) {
          for (let name of names) caches.delete(name);
        });
      }
    ''']);
  } catch (_) {}
}

/// Force a hard reload bypassing the browser cache
void hardReload() {
  try {
    // location.reload(true) is deprecated but still works in most browsers
    // Alternative: set a cache-bust query param
    final loc = html.window.location;
    final uri = Uri.parse(loc.href ?? '/');
    final busted = uri.replace(queryParameters: {
      ...uri.queryParameters,
      '_cb': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    loc.replace(busted.toString());
  } catch (_) {
    html.window.location.reload();
  }
}
