import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// TPIX Wallet — Sound Synthesizer
/// Generates audio from raw PCM data (compute in float64, output 16-bit WAV)
class SynthService {
  static final AudioPlayer _player = AudioPlayer();
  static final Map<String, String> _cache = {};

  /// Play a named sound effect (caches WAV files)
  static Future<void> _play(String name, Uint8List Function() generator) async {
    if (!_cache.containsKey(name)) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/tpix_$name.wav';
      await File(path).writeAsBytes(generator());
      _cache[name] = path;
    }
    await _player.stop();
    await _player.play(DeviceFileSource(_cache[name]!));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Splash screen — FF-inspired crystalline arpeggio
  static Future<void> playSplashMelody() => _play('splash', _genSplash);

  /// Send TPIX — whoosh sweep upward (departing energy)
  static Future<void> playSend() => _play('send', _genSend);

  /// Send success — triumphant confirmation fanfare
  static Future<void> playSendSuccess() => _play('send_ok', _genSendSuccess);

  /// Receive TPIX — coin drop ka-ching (rewarding)
  static Future<void> playReceive() => _play('receive', _genReceive);

  /// Error / warning — low dissonant buzz
  static Future<void> playError() => _play('error', _genError);

  /// Button tap — subtle soft click
  static Future<void> playTap() => _play('tap', _genTap);

  /// Notification alert — gentle 2-tone chime
  static Future<void> playNotification() => _play('notif', _genNotification);

  static Future<void> dispose() async {
    await _player.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Core rendering
  // ═══════════════════════════════════════════════════════════════════════════

  static Uint8List _renderNotes({
    required List<_Note> notes,
    required double totalSeconds,
    int sampleRate = 44100,
  }) {
    const numChannels = 2;
    final totalSamples = (sampleRate * totalSeconds).toInt();

    final left = Float64List(totalSamples);
    final right = Float64List(totalSamples);

    for (final note in notes) {
      _renderNote(note, left, right, sampleRate);
    }

    _normalize(left, right);

    final pcm = Int16List(totalSamples * numChannels);
    for (int i = 0; i < totalSamples; i++) {
      pcm[i * 2] = _f2i16(left[i]);
      pcm[i * 2 + 1] = _f2i16(right[i]);
    }

    return _createWav(pcm, sampleRate, numChannels);
  }

  static void _renderNote(
    _Note note,
    Float64List left,
    Float64List right,
    int sampleRate,
  ) {
    final startSample = (note.start * sampleRate).toInt();
    final numSamples = (note.duration * sampleRate).toInt();
    if (startSample + numSamples > left.length) return;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final env = note.envelope(t, note.duration);

      double sL = 0, sR = 0;
      for (final h in note.harmonics) {
        final f = note.freq * h.mul;
        sL += sin(2 * pi * f * 0.998 * t) * h.amp;
        sR += sin(2 * pi * f * 1.002 * t) * h.amp;
      }

      final idx = startSample + i;
      left[idx] += sL * env * note.velocity;
      right[idx] += sR * env * note.velocity;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Envelopes
  // ═══════════════════════════════════════════════════════════════════════════

  /// Crystal harp — fast pluck, exponential decay
  static double _envCrystal(double t, double dur) {
    const atk = 0.003;
    final decay = 4.0 / dur;
    double e = t < atk ? t / atk : exp(-(t - atk) * decay);
    return e * ((dur - t).clamp(0.0, 0.01) / 0.01);
  }

  /// Pad — smooth attack and release
  static double _envPad(double t, double dur) {
    const atk = 0.05;
    const rel = 0.1;
    double e = 1.0;
    if (t < atk) e = t / atk;
    if (t > dur - rel) e = ((dur - t) / rel).clamp(0.0, 1.0);
    return e * exp(-t * 1.5 / dur);
  }

  /// Percussive — instant attack, fast decay (for clicks/coins)
  static double _envPerc(double t, double dur) {
    const atk = 0.001;
    double e = t < atk ? t / atk : exp(-t * 12.0 / dur);
    return e * ((dur - t).clamp(0.0, 0.005) / 0.005);
  }

  /// Sweep — rises then falls
  static double _envSweep(double t, double dur) {
    final peak = dur * 0.3;
    double e;
    if (t < peak) {
      e = t / peak;
    } else {
      e = exp(-(t - peak) * 5.0 / dur);
    }
    return e * ((dur - t).clamp(0.0, 0.01) / 0.01);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Harmonic presets
  // ═══════════════════════════════════════════════════════════════════════════

  static const _hCrystal = [
    _H(1, 1.0), _H(2, 0.35), _H(3, 0.15), _H(4, 0.08), _H(5, 0.04),
  ];

  static const _hBell = [
    _H(1, 1.0), _H(2.76, 0.5), _H(4.07, 0.3), _H(5.2, 0.15), _H(6.98, 0.08),
  ];

  static const _hSoft = [
    _H(1, 1.0), _H(2, 0.2), _H(3, 0.05),
  ];

  static const _hBuzz = [
    _H(1, 1.0), _H(1.5, 0.6), _H(2.0, 0.4), _H(2.5, 0.3), _H(3.0, 0.2),
    _H(4.0, 0.15), _H(5.0, 0.1),
  ];

  static const _hClick = [
    _H(1, 1.0), _H(3, 0.3), _H(7, 0.1),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // Sound generators
  // ═══════════════════════════════════════════════════════════════════════════

  /// Splash — FF prelude arpeggio
  static Uint8List _genSplash() {
    return _renderNotes(totalSeconds: 2.3, notes: [
      // Ascending arpeggio
      _Note(freq: 523.25, start: 0.00, duration: 0.60, velocity: 0.50, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 659.25, start: 0.08, duration: 0.55, velocity: 0.55, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 783.99, start: 0.16, duration: 0.50, velocity: 0.60, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 987.77, start: 0.24, duration: 0.45, velocity: 0.65, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 1046.50, start: 0.32, duration: 0.50, velocity: 0.70, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 1318.51, start: 0.40, duration: 0.45, velocity: 0.72, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 1567.98, start: 0.48, duration: 0.42, velocity: 0.75, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 2093.00, start: 0.56, duration: 0.50, velocity: 0.70, harmonics: _hCrystal, envelope: _envCrystal),
      // Descending shimmer
      _Note(freq: 1567.98, start: 0.66, duration: 0.40, velocity: 0.45, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 1318.51, start: 0.72, duration: 0.40, velocity: 0.42, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 1046.50, start: 0.78, duration: 0.40, velocity: 0.40, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 987.77, start: 0.84, duration: 0.40, velocity: 0.38, harmonics: _hCrystal, envelope: _envCrystal),
      // Final resolve chord
      _Note(freq: 523.25, start: 0.95, duration: 1.20, velocity: 0.60, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 659.25, start: 0.95, duration: 1.15, velocity: 0.45, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 783.99, start: 0.95, duration: 1.10, velocity: 0.45, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 1046.50, start: 0.95, duration: 1.05, velocity: 0.50, harmonics: _hCrystal, envelope: _envCrystal),
      _Note(freq: 1567.98, start: 0.95, duration: 1.00, velocity: 0.35, harmonics: _hCrystal, envelope: _envCrystal),
    ]);
  }

  /// Send — rising whoosh sweep (energy departing)
  static Uint8List _genSend() {
    // Ascending sweep: low → high with airy timbre
    final notes = <_Note>[];
    const baseFreqs = [261.63, 329.63, 392.0, 523.25, 659.25, 783.99];
    for (int i = 0; i < baseFreqs.length; i++) {
      notes.add(_Note(
        freq: baseFreqs[i],
        start: i * 0.05,
        duration: 0.35 - i * 0.03,
        velocity: 0.3 + i * 0.08,
        harmonics: _hSoft,
        envelope: _envSweep,
      ));
    }
    // Trailing shimmer
    notes.add(_Note(freq: 1046.50, start: 0.30, duration: 0.30, velocity: 0.35, harmonics: _hCrystal, envelope: _envCrystal));
    return _renderNotes(totalSeconds: 0.65, notes: notes);
  }

  /// Send success — triumphant 3-note fanfare (like FF victory jingle start)
  static Uint8List _genSendSuccess() {
    return _renderNotes(totalSeconds: 1.2, notes: [
      // Bb4 → Bb4 → Bb4 → D5 ... iconic victory feel
      // Simplified: G5 → C6 → E6 chord resolve
      _Note(freq: 783.99, start: 0.00, duration: 0.20, velocity: 0.70, harmonics: _hCrystal, envelope: _envCrystal), // G5
      _Note(freq: 1046.50, start: 0.12, duration: 0.20, velocity: 0.75, harmonics: _hCrystal, envelope: _envCrystal), // C6
      _Note(freq: 1318.51, start: 0.24, duration: 0.25, velocity: 0.80, harmonics: _hCrystal, envelope: _envCrystal), // E6
      // Resolve chord ring-out
      _Note(freq: 523.25, start: 0.40, duration: 0.75, velocity: 0.55, harmonics: _hBell, envelope: _envCrystal), // C5
      _Note(freq: 659.25, start: 0.40, duration: 0.70, velocity: 0.45, harmonics: _hBell, envelope: _envCrystal), // E5
      _Note(freq: 783.99, start: 0.40, duration: 0.65, velocity: 0.45, harmonics: _hBell, envelope: _envCrystal), // G5
      _Note(freq: 1046.50, start: 0.40, duration: 0.60, velocity: 0.50, harmonics: _hBell, envelope: _envCrystal), // C6
      // Top sparkle
      _Note(freq: 2093.00, start: 0.42, duration: 0.50, velocity: 0.25, harmonics: _hSoft, envelope: _envCrystal), // C7
    ]);
  }

  /// Receive — coin drop ka-ching (metallic bell cascade)
  static Uint8List _genReceive() {
    return _renderNotes(totalSeconds: 0.9, notes: [
      // Metallic coin hits — bell harmonics
      _Note(freq: 2637.02, start: 0.00, duration: 0.15, velocity: 0.70, harmonics: _hBell, envelope: _envPerc), // E7
      _Note(freq: 3520.00, start: 0.03, duration: 0.12, velocity: 0.50, harmonics: _hBell, envelope: _envPerc), // A7
      // Ka-ching ring
      _Note(freq: 1318.51, start: 0.08, duration: 0.60, velocity: 0.65, harmonics: _hBell, envelope: _envCrystal), // E6
      _Note(freq: 1567.98, start: 0.10, duration: 0.55, velocity: 0.55, harmonics: _hBell, envelope: _envCrystal), // G6
      _Note(freq: 2093.00, start: 0.12, duration: 0.50, velocity: 0.50, harmonics: _hBell, envelope: _envCrystal), // C7
      // Warm undertone
      _Note(freq: 523.25, start: 0.10, duration: 0.50, velocity: 0.30, harmonics: _hSoft, envelope: _envPad), // C5
    ]);
  }

  /// Error — low dissonant warning buzz
  static Uint8List _genError() {
    return _renderNotes(totalSeconds: 0.5, notes: [
      // Two dissonant low tones
      _Note(freq: 130.81, start: 0.00, duration: 0.20, velocity: 0.60, harmonics: _hBuzz, envelope: _envPerc), // C3
      _Note(freq: 138.59, start: 0.00, duration: 0.20, velocity: 0.55, harmonics: _hBuzz, envelope: _envPerc), // C#3 (dissonant)
      // Second hit
      _Note(freq: 130.81, start: 0.18, duration: 0.25, velocity: 0.55, harmonics: _hBuzz, envelope: _envPerc), // C3
      _Note(freq: 123.47, start: 0.18, duration: 0.25, velocity: 0.50, harmonics: _hBuzz, envelope: _envPerc), // B2
    ]);
  }

  /// Tap — subtle soft click
  static Uint8List _genTap() {
    return _renderNotes(totalSeconds: 0.08, notes: [
      _Note(freq: 1800.0, start: 0.0, duration: 0.04, velocity: 0.25, harmonics: _hClick, envelope: _envPerc),
      _Note(freq: 3200.0, start: 0.0, duration: 0.03, velocity: 0.15, harmonics: _hClick, envelope: _envPerc),
    ]);
  }

  /// Notification — gentle 2-tone ascending chime
  static Uint8List _genNotification() {
    return _renderNotes(totalSeconds: 0.7, notes: [
      // Two gentle bell tones ascending
      _Note(freq: 1046.50, start: 0.00, duration: 0.35, velocity: 0.55, harmonics: _hBell, envelope: _envCrystal), // C6
      _Note(freq: 1318.51, start: 0.15, duration: 0.40, velocity: 0.60, harmonics: _hBell, envelope: _envCrystal), // E6
      // Soft pad underneath
      _Note(freq: 523.25, start: 0.0, duration: 0.50, velocity: 0.20, harmonics: _hSoft, envelope: _envPad), // C5
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DSP utilities
  // ═══════════════════════════════════════════════════════════════════════════

  static void _normalize(Float64List left, Float64List right) {
    double peak = 0;
    for (int i = 0; i < left.length; i++) {
      peak = max(peak, left[i].abs());
      peak = max(peak, right[i].abs());
    }
    if (peak < 0.001) return;
    final gain = 0.85 / peak;
    for (int i = 0; i < left.length; i++) {
      left[i] = _softClip(left[i] * gain);
      right[i] = _softClip(right[i] * gain);
    }
  }

  static double _softClip(double x) {
    if (x.abs() < 0.8) return x;
    return x.sign * (0.8 + 0.2 * _tanh((x.abs() - 0.8) / 0.2));
  }

  static double _tanh(double x) {
    final e2x = exp(2 * x);
    return (e2x - 1) / (e2x + 1);
  }

  static int _f2i16(double s) => (s.clamp(-1.0, 1.0) * 32767).toInt();

  // ═══════════════════════════════════════════════════════════════════════════
  // WAV builder
  // ═══════════════════════════════════════════════════════════════════════════

  static Uint8List _createWav(Int16List pcm, int sampleRate, int ch) {
    const bps = 16;
    final byteRate = sampleRate * ch * bps ~/ 8;
    final blockAlign = ch * bps ~/ 8;
    final dataSize = pcm.length * 2;

    final buf = ByteData(44 + dataSize);
    int o = 0;

    void str(String s) { for (int i = 0; i < s.length; i++) buf.setUint8(o++, s.codeUnitAt(i)); }
    void u32(int v) { buf.setUint32(o, v, Endian.little); o += 4; }
    void u16(int v) { buf.setUint16(o, v, Endian.little); o += 2; }

    str('RIFF'); u32(36 + dataSize); str('WAVE');
    str('fmt '); u32(16); u16(1); u16(ch); u32(sampleRate); u32(byteRate); u16(blockAlign); u16(bps);
    str('data'); u32(dataSize);

    for (int i = 0; i < pcm.length; i++) {
      buf.setInt16(o, pcm[i], Endian.little);
      o += 2;
    }

    return buf.buffer.asUint8List();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Data classes
// ═════════════════════════════════════════════════════════════════════════════

class _H {
  final double mul; // frequency multiplier
  final double amp; // amplitude
  const _H(this.mul, this.amp);
}

typedef _Envelope = double Function(double t, double duration);

class _Note {
  final double freq;
  final double start;
  final double duration;
  final double velocity;
  final List<_H> harmonics;
  final _Envelope envelope;

  const _Note({
    required this.freq,
    required this.start,
    required this.duration,
    this.velocity = 0.6,
    required this.harmonics,
    required this.envelope,
  });
}
