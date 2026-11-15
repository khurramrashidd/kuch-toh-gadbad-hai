import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class Narration {
  Narration(this.text, {required this.ai, this.model, this.cached = false});
  final String text;
  final bool ai;
  final String? model;
  final bool cached;
}

/// "Detective's notes": Gemini (Firebase AI Logic, free tier) turns the evidence
/// into plain language. Guard-rails: the model only sees our numbers, and every
/// number it writes must exist in the evidence - otherwise we fall back to the
/// pipeline's own template text. Good answers are cached in Firestore so the
/// demo never depends on rate limits.
class AiService {
  AiService({required this.firebaseReady, required this.models});
  final bool firebaseReady;
  final List<String> models;

  Narration template(CaseFile c, String lang) {
    final lines = <String>[c.verdict.headline(lang), c.verdict.detail(lang)];
    for (final ch in c.checks) {
      if (ch.status == 'pass' || ch.status == 'fail') lines.add('• ${ch.title(lang)}: ${ch.text(lang)}');
    }
    return Narration(lines.where((l) => l.trim().isNotEmpty).join('\n'), ai: false);
  }

  Map<String, dynamic> _evidence(CaseFile c) => {
        'case': c.title,
        'question': c.question,
        'variable': c.sourceShort,
        'units_per_decade': c.perDecade,
        'season': c.seasonLabel.isEmpty ? c.season : c.seasonLabel.first,
        'period': c.period,
        'regions': [
          for (final r in c.regions)
            {
              'name': r.name,
              'trend_per_decade': _r(r.trend.slopeDec),
              'p_value': _r(r.trend.p),
              'change_vs_noise': _r(r.trend.snr),
              'verdict': r.trend.verdictEn,
              'signal_emerged_year': r.trend.emerged ? r.trend.toe1?.round() : null,
            }
        ],
        'case_verdict': c.verdict.en,
        'checks': {for (final ch in c.checks) ch.key: '${ch.status}: ${ch.en}'},
      };

  static double? _r(double? v) {
    if (v == null || !v.isFinite) return null;
    if (v.abs() >= 100) return v.roundToDouble();
    if (v.abs() >= 1) return double.parse(v.toStringAsFixed(2));
    return double.parse(v.toStringAsPrecision(2));
  }

  String _prompt(CaseFile c, String lang) {
    final language = lang == 'hi'
        ? 'Hindi (Devanagari script, simple everyday Hindi; keep numbers in Western digits)'
        : 'simple English';
    return '''
You are "Inspector Dharti", a witty but scientifically careful Indian detective who explains NASA satellite evidence to the public.
Write the case summary in $language: 4 to 5 short sentences, at most 90 words, no markdown, no bullet points.
Rules:
- Use ONLY numbers that appear in the EVIDENCE JSON below. Never invent numbers, places, causes or studies.
- Say what is changing, where, how much per decade, and whether it is statistically significant (p-value below 0.05).
- Give the case verdict. A shared driver is evidence, not proof.
- If a region's verdict is "Not proven yet", say it is not proven yet - never say "no change".
- Finish with one sentence that starts with "${lang == 'hi' ? 'सावधानी:' : 'Caution:'}" naming one limitation of the evidence.
EVIDENCE JSON:
${jsonEncode(_evidence(c))}
''';
  }

  /// Every number in the AI text must match a number in the evidence (to its shown precision).
  bool grounded(String text, CaseFile c) {
    final allowed = <double>[];
    void add(double? v) {
      if (v == null || !v.isFinite) return;
      allowed.addAll([v, v.abs(), v * 100, (v * 100).abs()]);
    }

    for (final r in c.regions) {
      for (final v in [r.trend.slopeDec, r.trend.ciLoDec, r.trend.ciHiDec, r.trend.p, r.trend.snr, r.trend.toe1, r.trend.yearsNeeded]) {
        add(v);
      }
    }
    for (final y in c.period) {
      add(y.toDouble());
    }
    for (final d in c.drivers) {
      add(d.a.explained);
      add(d.b.explained);
    }
    final evText = jsonEncode(_evidence(c));
    for (final m in RegExp(r'-?\d+(?:\.\d+)?').allMatches(evText)) {
      add(double.tryParse(m.group(0)!));
    }
    for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(text)) {
      final s = m.group(0)!;
      final v = double.tryParse(s);
      if (v == null) continue;
      if (v <= 10 && !s.contains('.')) continue; // small counts like "two regions", "5 checks"
      final decimals = s.contains('.') ? s.split('.')[1].length : 0;
      final tol = 0.5 * _pow10(-decimals) + 1e-9;
      final ok = allowed.any((a) => (a - v).abs() <= tol || (a.abs() - v).abs() <= tol);
      if (!ok) return false;
    }
    return true;
  }

  static double _pow10(int e) {
    var r = 1.0;
    if (e >= 0) {
      for (var i = 0; i < e; i++) {
        r *= 10;
      }
    } else {
      for (var i = 0; i < -e; i++) {
        r /= 10;
      }
    }
    return r;
  }

  // ---- provider chain: the first one that answers wins -----------------------------------
  // 1. Gemini through Firebase AI Logic (needs App Check since Nov 2026)
  // 2. Gemini Developer API directly      (free key from aistudio.google.com)
  // 3. Groq                               (free key from console.groq.com)
  // 4. OpenRouter free router             (free key from openrouter.ai)
  // Keys come from build-time defines (keys.json, never committed). A missing key skips that provider.
  static const _geminiKey = String.fromEnvironment('GEMINI_KEY');
  static const _groqKey = String.fromEnvironment('GROQ_KEY');
  static const _openRouterKey = String.fromEnvironment('OPENROUTER_KEY');
  // Several keys per provider are allowed: write them comma-separated in keys.json.
  static List<String> _split(String raw) => [for (final k in raw.split(RegExp(r'[,;\s]+'))) if (k.trim().isNotEmpty) k.trim()];
  static final List<String> _geminiKeys = _split(_geminiKey);
  static final List<String> _groqKeys = _split(_groqKey);
  static final List<String> _openRouterKeys = _split(_openRouterKey);
  int _turn = 0; // each request starts from the next key, so the load is shared
  List<String> _rot(List<String> keys) => [for (var i = 0; i < keys.length; i++) keys[(i + _turn) % keys.length]];
  static bool _badKey(Object e) => '$e'.contains('HTTP 401') || '$e'.contains('HTTP 403');
  static const _groqModels = ['llama-3.3-70b-versatile', 'openai/gpt-oss-120b', 'llama-3.1-8b-instant'];
  static const _geminiDirect = ['gemini-3.5-flash-lite', 'gemini-3.6-flash', 'gemini-3.5-flash'];

  /// What is switched on (shown in the Lab so the team can see why AI is or is not answering).
  List<String> get providers => [
        if (firebaseReady) 'Firebase AI Logic',
        if (_geminiKeys.isNotEmpty) 'Gemini API (${_geminiKeys.length} key)',
        if (_groqKeys.isNotEmpty) 'Groq (${_groqKeys.length} key)',
        if (_openRouterKeys.isNotEmpty) 'OpenRouter (${_openRouterKeys.length} key)',
      ];
  String lastError = '';

  Future<String?> _openAiStyle(String url, String key, String model, String prompt, int maxTokens, double temp) async {
    final res = await http
        .post(Uri.parse(url),
            headers: {'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
              'max_tokens': maxTokens,
              'temperature': temp,
            }))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final choices = j['choices'] as List?;
    final msg = choices == null || choices.isEmpty ? null : (choices.first as Map)['message'] as Map?;
    return (msg?['content'] as String?)?.trim();
  }

  /// Returns (text, label of the model that answered), or null when every provider failed.
  /// [accept] lets the caller reject an answer (e.g. numbers not found in the data) and try the next one.
  Future<(String, String)?> generate(String prompt, {int maxTokens = 400, double temp = 0.4, bool Function(String)? accept, int minLen = 30}) async {
    bool ok(String? t) => t != null && t.length >= minLen && (accept == null || accept(t));
    final errors = <String>[];
    _turn++;
    if (firebaseReady) {
      for (final name in models) {
        try {
          final model = FirebaseAI.googleAI().generativeModel(model: name, generationConfig: GenerationConfig(temperature: temp, maxOutputTokens: maxTokens));
          final res = await model.generateContent([Content.text(prompt)]).timeout(const Duration(seconds: 25));
          final text = (res.text ?? '').trim();
          if (ok(text)) return (text, name);
        } catch (e) {
          errors.add('Firebase $name: $e');
        }
      }
    }
    for (final gKey in _rot(_geminiKeys)) {
      for (final name in _geminiDirect) {
        try {
          final res = await http
              .post(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$name:generateContent'),
                  headers: {'x-goog-api-key': gKey, 'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'contents': [
                      {
                        'parts': [
                          {'text': prompt}
                        ]
                      }
                    ],
                    'generationConfig': {'temperature': temp, 'maxOutputTokens': maxTokens},
                  }))
              .timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
          final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
          final cand = (j['candidates'] as List?)?.first as Map?;
          final parts = ((cand?['content'] as Map?)?['parts'] as List?) ?? const [];
          final text = parts.map((p) => (p as Map)['text'] ?? '').join().trim();
          if (ok(text)) return (text, name);
        } catch (e) {
          errors.add('Gemini $name: $e');
          if (_badKey(e)) break;
        }
      }
    }
    for (final qKey in _rot(_groqKeys)) {
      for (final name in _groqModels) {
        try {
          final text = await _openAiStyle('https://api.groq.com/openai/v1/chat/completions', qKey, name, prompt, maxTokens, temp);
          if (ok(text)) return (text!, 'Groq $name');
        } catch (e) {
          errors.add('Groq $name: $e');
          if (_badKey(e)) break;
        }
      }
    }
    for (final oKey in _rot(_openRouterKeys)) {
      try {
        final text = await _openAiStyle('https://openrouter.ai/api/v1/chat/completions', oKey, 'openrouter/free', prompt, maxTokens, temp);
        if (ok(text)) return (text!, 'OpenRouter free router');
      } catch (e) {
        errors.add('OpenRouter: $e');
      }
    }
    lastError = errors.isEmpty ? 'no AI provider is switched on' : errors.map((e) => e.length > 140 ? e.substring(0, 140) : e).join(' | ');
    return null;
  }

  Future<Narration> narrate(CaseFile c, String lang) async {
    final docId = '${c.id}_$lang';
    CollectionReference<Map<String, dynamic>>? col;
    if (firebaseReady) {
      col = FirebaseFirestore.instance.collection('narrations');
      try {
        final snap = await col.doc(docId).get().timeout(const Duration(seconds: 8));
        final data = snap.data();
        if (snap.exists && data != null && data['text'] is String) {
          return Narration(data['text'] as String, ai: true, model: data['model'] as String?, cached: true);
        }
      } catch (_) {}
    }
    final r = await generate(_prompt(c, lang), maxTokens: 400, temp: 0.4, minLen: 40, accept: (t) => grounded(t, c));
    if (r == null) return template(c, lang);
    if (col != null) _store(col, docId, r.$1, lang, c.id, r.$2);
    return Narration(r.$1, ai: true, model: r.$2);
  }

  Future<void> _store(CollectionReference<Map<String, dynamic>> col, String id, String text, String lang, String caseId, String model) async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      await col.doc(id).set({'text': text, 'lang': lang, 'case': caseId, 'model': model, 'created': FieldValue.serverTimestamp()});
    } catch (_) {
      // caching is best-effort
    }
  }

  /// Free-form suggestion text (clearly labelled as AI in the UI). Null when AI is unavailable.
  Future<(String, String)?> suggest(String prompt) => generate(prompt, maxTokens: 350, temp: 0.5);
}
