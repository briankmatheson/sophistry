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
const _purple = Color(0xFF7C5CBF);
const _purpleLight = Color(0xFFEDE7F6);
const _green = Color(0xFF4CAF50);
const _amber = Color(0xFFFFA726);
const _darkslategray = Color(0x2F4F4F99);

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

  // version info
  String backendVersion = '…';

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
    // Fetch backend version (non-blocking)
    api.getBackendVersion().then((v) {
      if (mounted) setState(() => backendVersion = v);
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
          // graph paper background
          Positioned.fill(
            child: CustomPaint(painter: _GraphPaperPainter()),
          ),
          // content
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
    const minWords = 100;
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
            valueColor: AlwaysStoppedAnimation<Color>(met ? _green : _purple),
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
    final details = previewResult?['score_details'] as Map<String, dynamic>? ?? {};
    final score0100 = (details['score_0_100'] as num?)?.toDouble() ?? 0;
    final band = details['band'] as String? ?? '';
    final notes = (details['notes'] as List<dynamic>?)?.cast<String>() ?? [];

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _purple.withOpacity(0.2)),
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
                      color: _purple.withOpacity(0.8),
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
                Expanded(child: _scoreColumn('You', r['user_score'], userClass, _green)),
                const SizedBox(width: 8),
                Expanded(child: _scoreColumn('Claude', r['claude_score'], claudeClass, _amber)),
                const SizedBox(width: 8),
                Expanded(child: _scoreColumn('Avg Human', r['human_avg_score'], avgClass, _purple)),
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
    final angleDeg = (clamped / 100.0) * 180.0 - 90.0;
    final angleRad = angleDeg * math.pi / 180.0;

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
          Positioned(
            bottom: 10,
            child: _Needle(angleRad: angleRad),
          ),
          Positioned(
            bottom: 4,
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
                    color: Colors.black.withOpacity(0.65),
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

class _Needle extends StatelessWidget {
  final double angleRad;
  const _Needle({required this.angleRad});

  @override
  Widget build(BuildContext context) {
    final needle = SizedBox(
      width: 6,
      height: sizeForNeedle(context),
      child: CustomPaint(painter: _NeedlePainter()),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: -math.pi / 2, end: angleRad),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (_, a, child) => Transform.rotate(angle: a, child: child),
      child: needle,
    );
  }

  double sizeForNeedle(BuildContext context) => 50;
}

class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.85);
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Hub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.85),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = math.min(size.width / 2, size.height) - 6;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withOpacity(0.18);

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, math.pi, math.pi, false, arcPaint);

    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = Colors.black.withOpacity(0.45);

    for (final t in [0, 40, 70, 90, 100]) {
      final a = (t / 100.0) * math.pi;
      final ang = math.pi + a;
      final p1 = Offset(
        center.dx + (radius - 1) * math.cos(ang),
        center.dy + (radius - 1) * math.sin(ang),
      );
      final p2 = Offset(
        center.dx + (radius - 10) * math.cos(ang),
        center.dy + (radius - 10) * math.sin(ang),
      );
      canvas.drawLine(p1, p2, tickPaint);
    }
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
