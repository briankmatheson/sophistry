// Legacy session reset widget — superseded by session.dart + main.dart _resetSession.
// Kept for reference. Uses cross-platform session.dart now.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'session.dart';
import 'config.dart';

/// Call the reset endpoint
Future<void> resetSession() async {
  await http.post(
    Uri.parse('${AppConfig.backendBaseUrl}/api/session/reset/'),
    headers: {'Content-Type': 'application/json'},
  );
  clearRunUuid();
  clearWebCaches();
  reloadPage();
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
