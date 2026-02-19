// Add this to your main app bar or scaffold.
// Uses universal_html for cookie access on web, http for the reset call.
//
// pubspec.yaml dependencies needed:
//   universal_html: ^2.2.4
//   http: ^1.2.0

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html;  // web only — use universal_html for multi-platform

const String kApiBase = 'https://app.sophistry.online';
const String kCookieName = 'sophistry_session';

/// Read the session UUID from the cookie (web only)
String? getSessionId() {
  final cookies = html.document.cookie ?? '';
  for (final cookie in cookies.split(';')) {
    final parts = cookie.trim().split('=');
    if (parts.length == 2 && parts[0] == kCookieName) {
      return parts[1];
    }
  }
  return null;
}

/// Call the reset endpoint — Django sets a new cookie in the response
Future<void> resetSession() async {
  await http.post(
    Uri.parse('$kApiBase/api/session/reset/'),
    headers: {'Content-Type': 'application/json'},
  );
  // Reload the page so the new cookie takes effect
  html.window.location.reload();
}

/// A simple icon button for the top-right of your AppBar
class SessionResetButton extends StatelessWidget {
  const SessionResetButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'New session',
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Start fresh?'),
            content: const Text(
              'This clears your current session and starts a new one. '
              'Your previous responses will still be saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reset'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await resetSession();
        }
      },
    );
  }
}

// Usage in your Scaffold:
//
// AppBar(
//   title: Text('Sophistry'),
//   actions: [
//     SessionResetButton(),
//   ],
// )
