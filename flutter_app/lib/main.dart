import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api.dart';
import 'config.dart';
import 'session.dart';

void main() => runApp(const SophistryApp());

// ─── palette ───────────────────────────────────────────────
const _purple = Color(0xFF7C5CBF);
const _purpleLight = Color(0xFFEDE7F6);
const _green = Color(0xFF4CAF50);
const _amber = Color(0xFFFFA726);

// ─── app root ──────────────────────────────────────────────
class SophistryApp extends StatelessWidget {
  const SophistryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sophistry',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: _purple,
          textTheme: GoogleFonts.architectsDaughterTextTheme(),
        ),
        home: const SophistryHome(),
      );
}

// ─── home: decides question flow vs review ─────────────────
class SophistryHome extends StatefulWidget {
  const SophistryHome({super.key});

  @override
  State<SophistryHome> createState() => _SophistryHomeState();
}

class _SophistryHomeState extends State<SophistryHome> {
  final api = SophistryApi();

  // state
  String? sessionId;
  String? runUuid;
  bool loading = true;
  bool inReview = false;

  // question flow
  Map<String, dynamic>? currentQuestion;
  int questionsAnswered = 0;
  final answerCtl = TextEditingController();
  final answerFocus = FocusNode();
  bool busy = false;
  String statusLine = '';

  // review data
  Map<String, dynamic>? reviewData;

  // add testcase
  bool canAddTestcase = false;
  final slugCtl = TextEditingController();
  final titleCtl = TextEditingController();
  final promptCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    sessionId = getSessionId();
    final savedRun = getSavedRunUuid();

    if (savedRun != null) {
      final savedProgress = getSavedProgress();

      // Completed all questions — try review
      if (savedProgress >= AppConfig.questionsPerSession) {
        try {
          final data = await api.getReview(savedRun);
          setState(() {
            runUuid = savedRun;
            reviewData = data;
            inReview = true;
            canAddTestcase = true;
            loading = false;
          });
          return;
        } catch (_) {
          // Review endpoint failed — show pending
          setState(() {
            runUuid = savedRun;
            inReview = true;
            canAddTestcase = true;
            loading = false;
            statusLine = 'Scores pending — check back soon';
          });
          return;
        }
      }

      // Mid-flow — resume question flow
      if (savedProgress > 0) {
        try {
          final q = await api.getQuestion(savedRun);
          setState(() {
            runUuid = savedRun;
            questionsAnswered = savedProgress;
            currentQuestion = q;
            loading = false;
            statusLine = q == null ? 'No more questions' : '';
          });
          if (q == null) await _loadReview();
          return;
        } catch (_) {
          // Fall through to new run
        }
      }
    }

    // New session — start question flow
    await _startNewRun();
  }

  Future<void> _startNewRun() async {
    setState(() {
      loading = true;
      inReview = false;
      questionsAnswered = 0;
      canAddTestcase = false;
      reviewData = null;
      statusLine = '';
    });
    try {
      final uuid = await api.createRun();
      final q = await api.getQuestion(uuid);
      setState(() {
        runUuid = uuid;
        currentQuestion = q;
        loading = false;
        statusLine = q == null ? 'No questions available' : '';
      });
      if (uuid.isNotEmpty) saveRunUuid(uuid);
    } catch (e) {
      setState(() {
        loading = false;
        statusLine = 'Error: $e';
      });
    }
  }

  Future<void> _submitAnswer() async {
    if (runUuid == null || currentQuestion == null) return;
    final ans = answerCtl.text.trim();
    if (ans.isEmpty) return;

    setState(() {
      busy = true;
      statusLine = 'Submitting…';
    });

    try {
      await api.submitAnswer(
        runUuid: runUuid!,
        testcaseId: (currentQuestion!['testcase_id'] as num).toInt(),
        answer: ans,
      );

      questionsAnswered++;
      answerCtl.clear();
      saveProgress(questionsAnswered);

      if (questionsAnswered >= AppConfig.questionsPerSession) {
        // Done — go to review
        await _loadReview();
      } else {
        // Next question
        final q = await api.getQuestion(runUuid!);
        setState(() {
          currentQuestion = q;
          busy = false;
          statusLine = q == null ? 'No more questions' : '';
        });
        if (q == null) {
          await _loadReview();
        } else {
          answerFocus.requestFocus();
        }
      }
    } catch (e) {
      setState(() {
        busy = false;
        statusLine = 'Error: $e';
      });
    }
  }

  Future<void> _loadReview() async {
    setState(() {
      busy = true;
      statusLine = 'Loading results…';
    });
    try {
      final data = await api.getReview(runUuid!);
      setState(() {
        reviewData = data;
        inReview = true;
        canAddTestcase = true;
        busy = false;
        statusLine = '';
      });
    } catch (e) {
      setState(() {
        inReview = true;
        canAddTestcase = true;
        busy = false;
        statusLine = 'Scores pending — check back soon';
      });
    }
  }

  Future<void> _resetSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start fresh?'),
        content: const Text(
          'This clears your session and starts a new run.\n'
          'Your previous responses are still saved.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (confirm == true) {
      clearRunUuid();
      try {
        await api.resetSession();
      } catch (_) {}
      reloadPage();
    }
  }

  Future<void> _addTestcase() async {
    slugCtl.clear();
    titleCtl.clear();
    promptCtl.clear();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a question'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(
                controller: slugCtl,
                decoration: const InputDecoration(labelText: 'slug (e.g. my-question)')),
            TextField(
                controller: titleCtl,
                decoration: const InputDecoration(labelText: 'title (optional)')),
            TextField(
                controller: promptCtl,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'question prompt')),
            const SizedBox(height: 8),
            const Text('Submissions are inactive until moderated.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final slug = slugCtl.text.trim();
              final prompt = promptCtl.text.trim();
              final title = titleCtl.text.trim();
              if (slug.isEmpty || prompt.isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                busy = true;
                statusLine = 'Submitting question…';
              });
              try {
                await api.submitTestcase(
                    slug: slug, prompt: prompt, title: title);
                setState(() => statusLine = 'Question submitted ✅');
              } catch (e) {
                setState(() => statusLine = 'Error: $e');
              } finally {
                setState(() => busy = false);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // ─── BUILD ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sophistry'),
        actions: [
          IconButton(
            onPressed: canAddTestcase && !busy ? _addTestcase : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add a question',
          ),
          IconButton(
            onPressed: busy ? null : _resetSession,
            icon: const Icon(Icons.refresh),
            tooltip: 'New session',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : inReview
              ? _buildReview()
              : _buildQuestionFlow(),
    );
  }

  // ─── QUESTION FLOW ─────────────────────────────────────
  Widget _buildQuestionFlow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // progress
          _progressBar(),
          const SizedBox(height: 12),
          // question card
          Expanded(
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: currentQuestion == null
                    ? Center(child: Text(statusLine.isEmpty ? 'No questions' : statusLine))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Question ${questionsAnswered + 1} of ${AppConfig.questionsPerSession}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentQuestion!['title'] ?? currentQuestion!['slug'] ?? '',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                currentQuestion!['prompt'] ?? '',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // answer input
          KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter &&
                  HardwareKeyboard.instance.isControlPressed &&
                  !busy &&
                  currentQuestion != null) {
                _submitAnswer();
              }
            },
            child: TextField(
              controller: answerCtl,
              focusNode: answerFocus,
              autofocus: true,
              enabled: !busy && currentQuestion != null,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Your answer',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy || currentQuestion == null ? null : _submitAnswer,
              child: Text(busy ? 'Submitting…' : 'Submit'),
            ),
          ),
          if (statusLine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(statusLine, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _progressBar() {
    final progress = questionsAnswered / AppConfig.questionsPerSession;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: _purpleLight,
            valueColor: const AlwaysStoppedAnimation<Color>(_purple),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$questionsAnswered of ${AppConfig.questionsPerSession} answered',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ─── REVIEW SCREEN ─────────────────────────────────────
  Widget _buildReview() {
    final results = reviewData?['results'] as List<dynamic>? ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          const Text('Your Results',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Session: ${runUuid ?? ""}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),

          if (results.isEmpty && statusLine.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(statusLine,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (ctx, i) => _reviewCard(results[i] as Map<String, dynamic>),
              ),
            ),

          if (statusLine.isNotEmpty && results.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(statusLine, style: const TextStyle(fontSize: 12)),
          ],

          // bottom legend
          const Divider(),
          _legendRow(),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final userClass = r['user_classification'] as Map<String, dynamic>?;
    final claudeClass = r['claude_classification'] as Map<String, dynamic>?;
    final avgClass = r['human_avg_classification'] as Map<String, dynamic>?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // question title
            Text(
              r['testcase_title'] ?? r['testcase_slug'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              r['prompt'] ?? '',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // your answer (collapsed)
            if (r['user_answer'] != null && (r['user_answer'] as String).isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Your answer',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(r['user_answer'],
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),

            const SizedBox(height: 8),

            // score comparison row
            Row(
              children: [
                Expanded(child: _scoreColumn('You', r['user_score'], userClass, _purple)),
                const SizedBox(width: 8),
                Expanded(child: _scoreColumn('Claude', r['claude_score'], claudeClass, _amber)),
                const SizedBox(width: 8),
                Expanded(child: _scoreColumn('Avg Human', r['human_avg_score'], avgClass, _green)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreColumn(
      String label, dynamic score, Map<String, dynamic>? classification, Color color) {
    final scoreVal = score != null ? (score as num).toDouble() : null;
    final icon = classification?['icon'] ?? '—';
    final level = classification?['level'] ?? 'Pending';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 2),
          Text(
            level,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
          if (scoreVal != null) ...[
            const SizedBox(height: 2),
            Text(
              scoreVal.toStringAsFixed(2),
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ] else
            Text('—', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _legendRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _legendItem('☀️ Noesis', 'Understanding'),
          _legendItem('📐 Dianoia', 'Reasoning'),
          _legendItem('🤝 Pistis', 'Belief'),
          _legendItem('🪞 Eikasia', 'Imagination'),
        ],
      ),
    );
  }

  Widget _legendItem(String icon, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
      ],
    );
  }
}
