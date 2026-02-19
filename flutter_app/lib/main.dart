import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api.dart';

void main() => runApp(const SophistryApp());



class SophistryApp extends StatelessWidget {
  const SophistryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sophistry',
        theme: ThemeData(
          useMaterial3: true,
          textTheme: GoogleFonts.architectsDaughterTextTheme(),
        ),
        home: const OneScreen(),
      );
}

class OneScreen extends StatefulWidget {
  const OneScreen({super.key});

  @override
  State<OneScreen> createState() => _OneScreenState();
}

class _OneScreenState extends State<OneScreen> {
  final api = SophistryApi();
  String? runUuid;
  Map<String, dynamic>? q;
  final answerCtl = TextEditingController();

  final slugCtl = TextEditingController();
  final titleCtl = TextEditingController();
  final promptCtl = TextEditingController();

  bool busy = false;
  String statusLine = 'Booting…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      busy = true;
      statusLine = 'Creating session…';
    });
    try {
      final uuid = await api.createRun();
      final question = await api.getQuestion(uuid);
      setState(() {
        runUuid = uuid;
        q = question;
        statusLine = 'Ready';
      });
    } catch (e) {
      setState(() => statusLine = 'Error: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _next() async {
    if (runUuid == null) return;
    setState(() {
      busy = true;
      statusLine = 'Loading…';
    });
    try {
      final question = await api.getQuestion(runUuid!);
      setState(() {
        q = question;
        answerCtl.clear();
        statusLine = 'Ready';
      });
    } catch (e) {
      setState(() => statusLine = 'Error: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    if (runUuid == null || q == null) return;
    final ans = answerCtl.text.trim();
    if (ans.isEmpty) return;

    setState(() {
      busy = true;
      statusLine = 'Submitting…';
    });
    try {
      await api.submitAnswer(
        runUuid: runUuid!,
        testcaseId: (q!['testcase_id'] as num).toInt(),
        answer: ans,
      );
      setState(() => statusLine = 'Saved ✅');
      await _next();
    } catch (e) {
      setState(() => statusLine = 'Error: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _addTestcase() async {
    slugCtl.clear();
    titleCtl.clear();
    promptCtl.clear();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add test case'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: slugCtl, decoration: const InputDecoration(labelText: 'slug')),
              TextField(controller: titleCtl, decoration: const InputDecoration(labelText: 'title (optional)')),
              TextField(controller: promptCtl, maxLines: 6, decoration: const InputDecoration(labelText: 'prompt')),
              const SizedBox(height: 8),
              const Text('Submissions are inactive by default (moderation gate).', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final slug = slugCtl.text.trim();
              final prompt = promptCtl.text.trim();
              final title = titleCtl.text.trim();
              if (slug.isEmpty || prompt.isEmpty) return;

              Navigator.pop(ctx);
              setState(() {
                busy = true;
                statusLine = 'Submitting testcase…';
              });
              try {
                await api.submitTestcase(slug: slug, prompt: prompt, title: title);
                setState(() => statusLine = 'Submitted ✅');
              } catch (e) {
                setState(() => statusLine = 'Error: $e');
              } finally {
                setState(() => busy = false);
              }
            },
            child: const Text('Submit'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sophistry'),
        actions: [
          IconButton(onPressed: busy ? null : _addTestcase, icon: const Icon(Icons.add_circle_outline)),
          IconButton(onPressed: busy ? null : _next, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              const Text('UUID:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(child: Text(runUuid ?? '…', style: const TextStyle(fontSize: 12))),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: q == null
                      ? Center(child: Text(statusLine))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(q!['slug'] ?? '', style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 8),
                            Expanded(child: SingleChildScrollView(child: Text(q!['prompt'] ?? '', style: const TextStyle(fontSize: 16)))),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: answerCtl,
              enabled: !busy,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Your answer', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton(onPressed: busy ? null : _submit, child: Text(busy ? 'Working…' : 'Submit'))),
            ]),
            const SizedBox(height: 8),
            Text(statusLine, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
