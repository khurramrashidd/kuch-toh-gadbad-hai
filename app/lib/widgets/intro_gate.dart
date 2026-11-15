import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Plays assets/intro/intro.mp4 once when the app opens, then shows [child].
/// If the file is missing or cannot play, the app opens straight away.
/// On the web the same file is played by a small HTML player in web/index.html instead.
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});
  final Widget child;
  static const asset = 'assets/intro/intro.mp4'; // 16:9, wide screens
  static const portraitAsset = 'assets/intro/intro_portrait.mp4'; // 9:16, upright phones (optional)
  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  VideoPlayerController? _c;
  bool _done = kIsWeb;

  @override
  void initState() {
    super.initState();
    if (!_done) _start();
  }

  Future<void> _start() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final have = manifest.listAssets();
      final view = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
      final upright = view.height > view.width;
      // upright screen: prefer the 9:16 file; otherwise the 16:9 one; either alone also works
      final order = upright ? [IntroGate.portraitAsset, IntroGate.asset] : [IntroGate.asset, IntroGate.portraitAsset];
      final pick = order.where(have.contains).firstOrNull;
      if (pick == null) return _finish();
      final c = VideoPlayerController.asset(pick);
      _c = c;
      await c.initialize().timeout(const Duration(seconds: 6));
      if (!mounted) return;
      c.addListener(() {
        final v = c.value;
        if (v.hasError || (v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 120))) _finish();
      });
      setState(() {});
      await c.play();
      // safety net: never keep the user waiting longer than the video plus a little
      Future<void>.delayed(c.value.duration + const Duration(seconds: 2), _finish);
    } catch (_) {
      _finish();
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    setState(() => _done = true);
    final c = _c;
    _c = null;
    c?.pause();
    Future<void>.delayed(const Duration(milliseconds: 1500), () => c?.dispose()); // after the fade has finished
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return widget.child;
    // When the video ends, the app fades in while growing from slightly far away.
    return ColoredBox(
      color: Colors.black,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1100),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween<double>(begin: child.key == const ValueKey('app') ? 0.84 : 1.2, end: 1).animate(anim), child: child),
        ),
        child: _done ? KeyedSubtree(key: const ValueKey('app'), child: widget.child) : KeyedSubtree(key: const ValueKey('intro'), child: _intro()),
      ),
    );
  }

  Widget _intro() {

    final c = _c;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          if (ready) Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
          Positioned(
            right: 12,
            top: 12,
            child: FilledButton.tonalIcon(onPressed: _finish, icon: const Icon(Icons.skip_next, size: 18), label: const Text('Skip')),
          ),
          const Positioned(
            left: 12,
            bottom: 10,
            child: Text('AI-generated video (Google Gemini)', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
          ),
        ]),
      ),
    );
  }
}
