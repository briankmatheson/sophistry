import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:math' as math;
import 'api.dart';
import 'config.dart';
import 'session.dart';

void main() => runApp(const SophistryApp());

// ─── palette ───────────────────────────────────────────────
const _darkslategray = Color(0xFF2F4F4F);
const _darkslategrayLight = Color(0xFFE0EDED);
const _green = Color(0xFF4CAF50);
const _amber = Color(0xFFFFA726);

// ─── Dial tooltips (F / B / R / U) ───────────────────────
class DialBandInfo {
  final String label;
  final String title;
  final String description;

  const DialBandInfo(this.label, this.title, this.description);
}

const _bandInfo = [
  DialBandInfo(
    'F',
    'Fluency',
    'Text exists but does not structurally address the question. Often generic, evasive, or off-topic.',
  ),
  DialBandInfo(
    'B',
    'Belief',
    'Matches the expected shape of an answer (definition/explanation), but may be shallow or incomplete.',
  ),
  DialBandInfo(
    'R',
    'Reasoning',
    'Shows structured explanation with causal links and multi-step logic tied to the prompt.',
  ),
  DialBandInfo(
    'U',
    'Understanding',
    'Fully aligned structure with distinctions, constraints, and conceptual clarity.',
  ),
];

// ─── app root ──────────────────────────────────────────────
class SophistryApp extends StatelessWidget {
  const SophistryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sophistry',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: _darkslategray,
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

  // live preview scoring
  Map<String, dynamic>? previewResult;
  Timer? _previewTimer;
  String? _lastPreviewText;
  int _wordCount = 0;

  // check (validate-only) result — triggered by explicit button
  Map<String, dynamic>? checkResult;
  bool checking = false;

  // server info (fetched from /api/mobile/info)
  String backendVersion = '…';
  int serverMinWords = 42;
  int serverMinSentences = 3;

  @override
  void initState() {
    super.initState();
    answerCtl.addListener(_onAnswerChanged);
    _init();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    answerCtl.removeListener(_onAnswerChanged);
    answerCtl.dispose();
    answerFocus.dispose();
    slugCtl.dispose();
    titleCtl.dispose();
    promptCtl.dispose();
    super.dispose();
  }

  void _onAnswerChanged() {
    final text = answerCtl.text.trim();

    // Word count updates immediately on every keystroke
    final wc = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
    if (wc != _wordCount) {
      setState(() => _wordCount = wc);
    }

    // Preview scoring is debounced
    if (text == _lastPreviewText) return;
    _lastPreviewText = text;

    _previewTimer?.cancel();

    // Clear preview immediately if empty
    if (text.isEmpty) {
      setState(() => previewResult = null);
      return;
    }

    // Debounce: wait 600ms after typing stops
    _previewTimer = Timer(const Duration(milliseconds: 600), () {
      _fetchPreview(text);
    });
  }

  Future<void> _fetchPreview(String text) async {
    if (currentQuestion == null) return;
    final tcId = (currentQuestion!['testcase_id'] as num).toInt();
    try {
      final result = await api.previewScore(testcaseId: tcId, answer: text);
      // Only update if the text hasn't changed since we fired
      if (answerCtl.text.trim() == text && mounted) {
        setState(() => previewResult = result);
      }
    } catch (_) {
      // Silently ignore preview errors — don't disrupt the flow
    }
  }

  Future<void> _init() async {
    // Fetch server constants (non-blocking)
    api.getInfo().then((info) {
      if (mounted) {
        setState(() {
          backendVersion = info['version'] as String? ?? '?';
          serverMinWords = (info['min_words'] as num?)?.toInt() ?? 42;
          serverMinSentences = (info['min_sentences'] as num?)?.toInt() ?? 3;
        });
      }
    }).catchError((_) {
      // Fall back to getBackendVersion if info endpoint unavailable
      api.getBackendVersion().then((v) {
        if (mounted) setState(() => backendVersion = v);
      });
    });

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

  Future<void> _checkAnswer() async {
    final ans = answerCtl.text.trim();
    if (ans.isEmpty) return;

    setState(() {
      checking = true;
      checkResult = null;
      statusLine = '';
    });

    try {
      final result = await api.validate(
        testcaseId: currentQuestion != null
            ? (currentQuestion!['testcase_id'] as num).toInt()
            : null,
        prompt: currentQuestion?['prompt'] as String?,
        answer: ans,
      );
      if (mounted) {
        setState(() {
          checkResult = result;
          checking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          checking = false;
          statusLine = 'Check error: $e';
        });
      }
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
      _previewTimer?.cancel();
      _lastPreviewText = null;
      _wordCount = 0;
      previewResult = null;
      checkResult = null;
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
      backgroundColor: const Color(0xFFFBFBF8),
      appBar: AppBar(
        title: const Text('Sophistry'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                'fe ${AppConfig.appVersion} · be $backendVersion',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ),
          ),
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
      body: Stack(
        children: [
          loading
              ? const Center(child: CircularProgressIndicator())
              : inReview
                  ? _buildReview()
                  : _buildQuestionFlow(),
        ],
      ),
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
              color: Colors.white.withOpacity(0.85),
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
          // ─── live preview ───────────────────────────────
          if (previewResult != null) _buildPreviewFeedback(),
          // ─── check result (explicit validate) ───────────
          if (checkResult != null) _buildCheckResult(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || checking || answerCtl.text.trim().isEmpty
                      ? null
                      : _checkAnswer,
                  child: Text(checking ? 'Checking…' : 'Check'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: busy || currentQuestion == null ? null : _submitAnswer,
                  child: Text(busy ? 'Submitting…' : 'Submit'),
                ),
              ),
            ],
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
    final minWords = serverMinWords;
    const maxDisplay = 110; // 110% scale
    final pct = (_wordCount / minWords).clamp(0.0, maxDisplay / 100.0);
    final barValue = (pct * 100.0 / (maxDisplay / 100.0)).clamp(0.0, 100.0) / 100.0;
    final met = _wordCount >= minWords;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: barValue,
            minHeight: 8,
            backgroundColor: _darkslategray,
            valueColor: AlwaysStoppedAnimation<Color>(met ? _green : _darkslategray),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$_wordCount / $minWords words${met ? " ✓" : ""}',
          style: TextStyle(
            fontSize: 11,
            color: met ? _green : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // ─── LIVE PREVIEW FEEDBACK ──────────────────────────────
  Widget _buildPreviewFeedback() {
    // score_details from API contains the structural_scoring payload
    final scoreDetails = previewResult?['score_details'] as Map<String, dynamic>? ?? {};
    final innerDetails = scoreDetails['score_details'] as Map<String, dynamic>? ?? {};
    // structural_score is 0..1
    final rawScore = (innerDetails['structural_score'] as num?)?.toDouble() ??
        (scoreDetails['score'] as num?)?.toDouble() ??
        0;
    final score0100 = rawScore <= 1.0 ? rawScore * 100.0 : rawScore;
    // Extract explain lines for coaching notes
    final explain = (innerDetails['explain'] as List<dynamic>?)?.cast<String>() ?? [];
    // Fallback: old-style notes
    final notes = explain.isNotEmpty
        ? explain
        : (scoreDetails['notes'] as List<dynamic>?)?.cast<String>() ?? [];
    // Band from flags
    final flags = innerDetails['flags'] as Map<String, dynamic>?;
    String band = '';
    if (score0100 >= 90) {
      band = 'UNDERSTANDING';
    } else if (score0100 >= 70) {
      band = 'REASONING';
    } else if (score0100 >= 40) {
      band = 'BELIEF';
    } else {
      band = 'FLUENCY';
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _darkslategray.withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // structural similarity dial
            SophistryDial(score: score0100, size: const Size(80, 44)),
            const SizedBox(width: 12),
            // band + coaching notes
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    band,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _darkslategray.withOpacity(0.8),
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ...notes.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        n,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CHECK RESULT (explicit validate button) ─────────
  Widget _buildCheckResult() {
    final validation = checkResult?['validation'] as Map<String, dynamic>? ?? {};
    final scored = checkResult?['scored'] == true;
    final wordsOk = validation['words_ok'] == true;
    final sentencesOk = validation['sentences_ok'] == true;
    final allOk = validation['ok'] == true;
    final wc = validation['word_count'] ?? 0;
    final sc = validation['sentence_count'] ?? 0;
    final minW = validation['min_words'] ?? 42;
    final minS = validation['min_sentences'] ?? 3;

    // If scored, extract the structural score for the dial
    double? dialScore;
    if (scored) {
      final scoreDetails = checkResult?['score_details'] as Map<String, dynamic>? ?? {};
      final rawScore = scoreDetails['score'] as num? ?? 0;
      // score is 0..1 from structural_scoring
      dialScore = (rawScore.toDouble() * 100.0).clamp(0.0, 100.0);
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: allOk
              ? _green.withOpacity(0.06)
              : Colors.orange.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: allOk
                ? _green.withOpacity(0.3)
                : Colors.orange.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Validation row
            Row(
              children: [
                Icon(
                  allOk ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 18,
                  color: allOk ? _green : Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  allOk ? 'Validation passed' : 'Needs more work',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: allOk ? _green : Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Words: $wc / $minW ${wordsOk ? "✓" : "✗"}    '
              'Sentences: $sc / $minS ${sentencesOk ? "✓" : "✗"}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
              ),
            ),
            // Scoring section — only when both question + answer present
            if (scored && dialScore != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SophistryDial(score: dialScore, size: const Size(80, 44)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Structural alignment',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _darkslategray.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Score: ${dialScore.round()} / 100',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        ),
                        if (checkResult?['score_details'] != null) ...[
                          const SizedBox(height: 2),
                          ..._explainLines(checkResult!['score_details'] as Map<String, dynamic>),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (!scored) ...[
              const SizedBox(height: 4),
              Text(
                'Add a question to also see the alignment score.',
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey[500]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _explainLines(Map<String, dynamic> scoreDetails) {
    final explain = (scoreDetails['score_details'] as Map<String, dynamic>?)?['explain'] as List<dynamic>?;
    if (explain == null || explain.isEmpty) return [];
    return explain.take(3).map((e) => Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(
        e.toString(),
        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
      ),
    )).toList();
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
    Map<String, dynamic>? _asClassMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is String) return {'level': v, 'icon': '—'};
      return null;
    }
    final userClass = _asClassMap(r['user_classification']);
    final claudeClass = _asClassMap(r['claude_classification']);
    final avgClass = _asClassMap(r['human_avg_classification']);

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
                Expanded(child: _scoreColumn('You', r['user_score'], userClass, _green)),
                const SizedBox(width: 8),
                Expanded(child: _scoreColumn('Claude', r['claude_score'], claudeClass, _amber)),
                const SizedBox(width: 8),
                Expanded(child: _scoreColumn('Avg Human', r['human_avg_score'], avgClass, _darkslategray)),
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
    final dialScore = scoreVal == null
        ? null
        : (scoreVal <= 1.5 ? (scoreVal * 100.0) : (scoreVal <= 100.0 ? scoreVal : 100.0));
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
          if (dialScore != null)
            SophistryDial(score: dialScore!, size: const Size(120, 66))
          else
            Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(
            level,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
          if (scoreVal != null) ...[
            const SizedBox(height: 2),
            Text(
              dialScore!.round().toString(),
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

// ─── Sophistry Dial (instrument-style) ────────────────────
class SophistryDial extends StatelessWidget {
  final double score; // expected 0..100
  final Size size;

  const SophistryDial({
    super.key,
    required this.score,
    this.size = const Size(140, 78),
  });

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0.0, 100.0);
    // 0 = far left (9 o'clock), 100 = far right (3 o'clock)
    final angleRad = ((clamped / 100.0) * math.pi) - (math.pi / 2);
    final radius = math.min(size.width / 2, size.height) - 6;
    final needleLen = radius * 0.72;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          CustomPaint(
            size: size,
            painter: _DialPainter(),
          ),
          DialLabelOverlay(
            size: size,
            thresholds: const [0, 40, 70, 90],
          ),
          // Needle — painted with canvas pivot at bottom-center (hub)
          Positioned(
            bottom: 0,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: -math.pi / 2, end: angleRad),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                builder: (_, a, __) => CustomPaint(
                  size: size,
                  painter: _NeedlePainter(angleRad: a, needleLength: needleLen),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -1,
            child: _Hub(),
          ),
        ],
      ),
    );
  }
}

class DialLabelOverlay extends StatelessWidget {
  final Size size;
  final List<int> thresholds; // [0, 40, 70, 90]

  const DialLabelOverlay({
    super.key,
    required this.size,
    required this.thresholds,
  });

  @override
  Widget build(BuildContext context) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h);
    final radius = math.min(w / 2, h) - 6;

    Offset anchorFor(int t) {
      final a = (t / 100.0) * math.pi;
      final ang = math.pi + a;
      final r = radius - 22;
      return Offset(
        center.dx + r * math.cos(ang),
        center.dy + r * math.sin(ang),
      );
    }

    return Stack(
      children: List.generate(_bandInfo.length, (i) {
        final pos = anchorFor(thresholds[i]);
        return Positioned(
          left: pos.dx - 14,
          top: pos.dy - 14,
          child: Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 4),
            message: "${_bandInfo[i].title}\n\n${_bandInfo[i].description}",
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: Text(
                  _bandInfo[i].label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withOpacity(0.88),
                    shadows: const [
                      Shadow(
                        blurRadius: 2,
                        offset: Offset(0, 1),
                        color: Color(0xAA000000),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  final double angleRad;
  final double needleLength;

  _NeedlePainter({required this.angleRad, required this.needleLength});

  @override
  void paint(Canvas canvas, Size size) {
    // Pivot at bottom-center of the dial (the hub point)
    final pivot = Offset(size.width / 2, size.height);

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angleRad);

    // Needle points upward from pivot (negative Y)
    const halfW = 1.8;
    final tip = -needleLength;

    // Shadow
    final shadowPath = Path()
      ..moveTo(0, tip + 1)
      ..lineTo(halfW + 0.4, 0)
      ..lineTo(-halfW - 0.4, 0)
      ..close();
    canvas.drawPath(shadowPath, Paint()..color = const Color(0x44000000));

    // Red needle
    final needlePath = Path()
      ..moveTo(0, tip)
      ..lineTo(halfW, 0)
      ..lineTo(-halfW, 0)
      ..close();
    canvas.drawPath(needlePath, Paint()..color = const Color(0xFFE53935));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter old) =>
      old.angleRad != angleRad || old.needleLength != needleLength;
}

class _Hub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0B0B0B),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Instrument panel background (dark, high-contrast)
    final bg = Paint()..color = const Color(0xFF0B0B0B);
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(8),
    );
    canvas.drawRRect(panel, bg);

    final center = Offset(size.width / 2, size.height);
    final radius = math.min(size.width / 2, size.height) - 6;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1A1A1A);

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, math.pi, math.pi, false, arcPaint);

    // Red zone overlay (high scores)
    final redZonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4A0B0B);
    // 80..100 mapped onto 180deg sweep
    final startA = math.pi + (80 / 100.0) * math.pi;
    final sweepA = (20 / 100.0) * math.pi;
    canvas.drawArc(rect, startA, sweepA, false, redZonePaint);

    // Ticks: minor/major with high contrast
    for (int t = 0; t <= 100; t += 5) {
      final isMajor = (t % 20 == 0);
      final isMedium = (!isMajor && (t % 10 == 0));

      final tickLen = isMajor
          ? 14.0
          : isMedium
              ? 10.0
              : 7.0;
      final tickW = isMajor
          ? 2.2
          : isMedium
              ? 1.6
              : 1.1;

      final a = (t / 100.0) * math.pi;
      final ang = math.pi + a;
      final pOuter = Offset(
        center.dx + (radius - 0.5) * math.cos(ang),
        center.dy + (radius - 0.5) * math.sin(ang),
      );
      final pInner = Offset(
        center.dx + (radius - tickLen) * math.cos(ang),
        center.dy + (radius - tickLen) * math.sin(ang),
      );

      final inRedZone = (t >= 80);
      final tickPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tickW
        ..strokeCap = StrokeCap.round
        ..color = inRedZone ? const Color(0xFFE53935) : Colors.white;

      canvas.drawLine(pOuter, pInner, tickPaint);
    }

    // A faint inner arc highlight for depth
    final innerArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.08);
    final innerRect = Rect.fromCircle(center: center, radius: radius - 6);
    canvas.drawArc(innerRect, math.pi, math.pi, false, innerArcPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── GRAPH PAPER BACKGROUND ─────────────────────────────
class _GraphPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Thin grid lines (12px)
    final thinPaint = Paint()
      ..color = const Color(0x0F000000) // ~6% opacity
      ..strokeWidth = 0.5;

    for (double x = 0; x <= size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thinPaint);
    }
    for (double y = 0; y <= size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), thinPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
