import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Future<Narration> narrate(CaseFile c, String lang) async {
    if (!firebaseReady) return template(c, lang);
    final docId = '${c.id}_$lang';
    final col = FirebaseFirestore.instance.collection('narrations');
    try {
      final snap = await col.doc(docId).get().timeout(const Duration(seconds: 8));
      final data = snap.data();
      if (snap.exists && data != null && data['text'] is String) {
        return Narration(data['text'] as String, ai: true, model: data['model'] as String?, cached: true);
      }
    } catch (_) {}
    for (final name in models) {
      try {
        final model = FirebaseAI.googleAI().generativeModel(
          model: name,
          generationConfig: GenerationConfig(temperature: 0.4, maxOutputTokens: 400),
        );
        final res = await model.generateContent([Content.text(_prompt(c, lang))]).timeout(const Duration(seconds: 30));
        final text = (res.text ?? '').trim();
        if (text.length < 40 || !grounded(text, c)) continue;
        _store(col, docId, text, lang, c.id, name);
        return Narration(text, ai: true, model: name);
      } catch (_) {
        continue;
      }
    }
    return template(c, lang);
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
  Future<String?> suggest(String prompt) async {
    if (!firebaseReady) return null;
    for (final name in models) {
      try {
        final model = FirebaseAI.googleAI().generativeModel(model: name, generationConfig: GenerationConfig(temperature: 0.5, maxOutputTokens: 350));
        final res = await model.generateContent([Content.text(prompt)]).timeout(const Duration(seconds: 30));
        final text = (res.text ?? '').trim();
        if (text.length > 30) return text;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
