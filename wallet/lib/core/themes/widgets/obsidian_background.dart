/// TPIX Wallet — พื้นหลังธีม Obsidian
///
/// ชั้นจากล่างขึ้นบน (ตาม Main.dc.html):
///   1. พื้นดำ #07080C เต็มจอ
///   2. คลิปเทควนลูป (ไม่มีเสียง) กว้างเต็มจอ สูง ~68% ของจอ จัดแบบ cover
///      — ระหว่างรอเฟรมแรก / เปิด "ลดภาพเคลื่อนไหว" / เล่นไม่ได้ → ภาพนิ่ง (poster)
///   3. ไล่สีดำทับ: บนสุดเกือบใส → ลงมาราว 69% ของจอเป็นดำทึบ
///   4. เนื้อหาแอป
///
/// กฎที่ต้องรักษา:
///   - แอปลงพื้นหลัง (ปิดจอ/สลับแอป) = หยุดคลิปทันที กลับมาค่อยเล่นต่อ
///   - ผู้ใช้เปิด "ลดภาพเคลื่อนไหว" ในเครื่อง = ไม่สร้างตัวเล่นวิดีโอเลย ใช้ภาพนิ่ง
///   - ตัวเล่นวิดีโอต้องถูก dispose ทุกทาง (สลับธีม / ปิดแอป / เปิดลดภาพเคลื่อนไหวกลางทาง)
///
/// Developed by Xman Studio
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../obsidian_tokens.dart';

class ObsidianBackground extends StatefulWidget {
  final Widget child;

  const ObsidianBackground({super.key, required this.child});

  static const videoAsset = 'assets/obsidian/video/bg_loop.mp4';
  static const posterAsset = 'assets/obsidian/video/bg_loop_poster.jpg';

  /// สัดส่วนความสูงของคลิปต่อความสูงจอ (mock: 574 / 844)
  static const double videoHeightFactor = 574 / 844;

  /// เทสต์ปิดวิดีโอได้ (ไม่มีปลั๊กอินเล่นวิดีโอใน flutter test) — ใช้ภาพนิ่งแทน
  @visibleForTesting
  static bool enableVideo = true;

  @override
  State<ObsidianBackground> createState() => _ObsidianBackgroundState();
}

class _ObsidianBackgroundState extends State<ObsidianBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;

  /// เฟรมแรกขึ้นจอแล้วหรือยัง — ก่อนหน้านั้นโชว์ภาพนิ่งทับไว้ (กันจอดำแวบ)
  bool _firstFrame = false;

  /// ปิดวิดีโอเพราะผู้ใช้ตั้ง "ลดภาพเคลื่อนไหว"
  bool _reduceMotion = false;

  /// แอปอยู่หน้าจออยู่ไหม (ไม่ใช่ลงพื้นหลัง)
  bool _foreground = true;

  /// ตัวนับรุ่นของตัวเล่น — งาน async ของตัวเก่าที่เพิ่งเสร็จต้องไม่ไปแตะตัวใหม่
  int _generation = 0;

  /// เล่นไม่ได้มาแล้วครั้งหนึ่ง → ไม่ลองซ้ำ (กันวนสร้างตัวเล่นใหม่ทุกครั้งที่ MediaQuery ขยับ)
  bool _videoFailed = false;

  /// didChangeDependencies รอบแรกผ่านแล้ว
  bool _depsReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // อ่านค่า "ลดภาพเคลื่อนไหว" ทุกครั้งที่ MediaQuery เปลี่ยน (ผู้ใช้สลับได้กลางทาง)
    // (ผูกเฉพาะค่านี้ของ MediaQuery — คีย์บอร์ดเด้ง/หมุนจอ ไม่ทำให้มาที่นี่)
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_depsReady || reduce != _reduceMotion) {
      _depsReady = true;
      _reduceMotion = reduce;
      if (reduce) {
        _disposeVideo();
      } else {
        _startVideo();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    if (_foreground) {
      v.play();
    } else {
      // ลงพื้นหลัง → หยุดถอดรหัสวิดีโอทันที (ประหยัดแบต/ซีพียู)
      v.pause();
    }
  }

  void _startVideo() {
    if (!ObsidianBackground.enableVideo || _video != null || _videoFailed) return;
    final gen = ++_generation;
    final v = VideoPlayerController.asset(
      ObsidianBackground.videoAsset,
      // ไม่แย่งเสียงจากแอปเพลงที่ผู้ใช้เปิดอยู่ — คลิปนี้ไม่มีเสียงอยู่แล้ว
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _video = v;
    v.addListener(_onVideoTick);
    unawaited(_initVideo(v, gen));
  }

  Future<void> _initVideo(VideoPlayerController v, int gen) async {
    try {
      await v.initialize();
      // ระหว่างรอ: ถูก dispose / สลับรุ่น / ปิดภาพเคลื่อนไหว → ทิ้งเงียบ ๆ
      if (!mounted || gen != _generation) return;
      await v.setVolume(0);
      await v.setLooping(true);
      if (!mounted || gen != _generation) return;
      if (_foreground) await v.play();
    } catch (e) {
      // เล่นไม่ได้ (เครื่องไม่รองรับ / ไม่มีปลั๊กอินในเทสต์) → ใช้ภาพนิ่งต่อไป
      // ไม่โชว์ข้อความอะไรให้ผู้ใช้ — พื้นหลังเป็นของตกแต่ง ไม่ใช่ฟีเจอร์
      debugPrint('ObsidianBackground video unavailable: ${e.runtimeType}');
      if (mounted && gen == _generation) {
        _videoFailed = true;
        _disposeVideo();
        setState(() {});
      }
    }
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null || _firstFrame) return;
    // ถือว่าเฟรมแรกขึ้นแล้วเมื่อเริ่มเดินจริง (ตำแหน่ง > 0) — isInitialized อย่างเดียว
    // บนแอนดรอยด์บางรุ่นยังเป็นจอดำอยู่ครู่หนึ่ง
    if (v.value.isInitialized && v.value.isPlaying && v.value.position > Duration.zero) {
      if (mounted) setState(() => _firstFrame = true);
    }
  }

  void _disposeVideo() {
    _generation++;
    final v = _video;
    _video = null;
    if (v != null) {
      v.removeListener(_onVideoTick);
      unawaited(v.dispose());
    }
    // ไม่ setState ที่นี่ — ถูกเรียกจาก didChangeDependencies ซึ่ง build ตามมาอยู่แล้ว
    _firstFrame = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    final v = _video;
    _video = null;
    if (v != null) {
      v.removeListener(_onVideoTick);
      unawaited(v.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    final showVideo = v != null && v.value.isInitialized && !_reduceMotion;

    return ColoredBox(
      color: ObsidianColors.ground,
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight.isFinite ? box.maxHeight : 844.0;
          final videoH = h * ObsidianBackground.videoHeightFactor;
          return Stack(
            fit: StackFit.expand,
            children: [
              // ── คลิป / ภาพนิ่ง (ไม่รับการแตะ) ──
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: videoH,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: RepaintBoundary(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (showVideo)
                            FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: v.value.size.width,
                                height: v.value.size.height,
                                child: VideoPlayer(v),
                              ),
                            ),
                          // ภาพนิ่งทับไว้จนกว่าเฟรมแรกจะขึ้น แล้วค่อยจางออก
                          AnimatedOpacity(
                            opacity: showVideo && _firstFrame ? 0 : 1,
                            duration: const Duration(milliseconds: 400),
                            child: Image.asset(
                              ObsidianBackground.posterAsset,
                              fit: BoxFit.cover,
                              // ถอดรหัสแค่ขนาดที่จอใช้ ไม่ต้องเต็มไฟล์
                              cacheWidth: 544,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── ไล่ดำทับ (ค่าจาก mock: 0 / 250 / 500 / 580 จากจอสูง 844) ──
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x0D07080C), // .05
                          Color(0x6607080C), // .40
                          Color(0xEB07080C), // .92
                          ObsidianColors.ground,
                          ObsidianColors.ground,
                        ],
                        stops: [0.0, 250 / 844, 500 / 844, 580 / 844, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // ── เนื้อหาแอป ──
              Positioned.fill(child: widget.child),
            ],
          );
        },
      ),
    );
  }
}
