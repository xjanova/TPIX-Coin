import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

/// Living Identity Recovery Service
/// Recovery = ตอบคำถาม 3/5 ข้อถูก + อยู่ในรัศมี 200m ของจุดที่ลงทะเบียน
///
/// Security Questions: hashed with PBKDF2-like iteration (SHA-256 x 10,000)
/// Location: GPS coordinates rounded to grid (~111m), stored as hash only
/// Rate Limiting: 5 attempts, 5-minute lockout
class IdentityService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Storage keys
  static const _keyQuestions = 'tpix_identity_questions';
  static const _keyLocations = 'tpix_identity_locations';
  static const _keyRecoveryPin = 'tpix_identity_recovery_pin';
  static const _keyAttempts = 'tpix_identity_attempts';

  // Rate limiting
  static const int maxAttempts = 5;
  static const int lockoutMinutes = 5;

  // Location grid precision: 3 decimal places ≈ 111m
  static const int gridPrecision = 3;
  // Max registered locations
  static const int maxLocations = 3;

  // ================================================================
  // Security Questions
  // ================================================================

  /// Save security questions (3-5 Q&A pairs)
  /// Answers are hashed, never stored in plaintext
  Future<void> setSecurityQuestions(List<Map<String, String>> qaPairs) async {
    if (qaPairs.length < 3 || qaPairs.length > 5) {
      throw Exception('Need 3-5 security questions');
    }

    final stored = qaPairs.map((qa) {
      final question = qa['question'] ?? '';
      final answer = qa['answer'] ?? '';
      if (question.isEmpty || answer.isEmpty) {
        throw Exception('Question and answer are required');
      }
      final salt = _generateSalt();
      final hash = _hashAnswer(answer, salt);
      return {'question': question, 'salt': salt, 'hash': hash};
    }).toList();

    await _storage.write(key: _keyQuestions, value: jsonEncode(stored));
  }

  /// Get stored questions (without answers)
  Future<List<String>> getQuestions() async {
    final json = await _storage.read(key: _keyQuestions);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((q) => q['question'] as String).toList();
  }

  /// Verify answers — returns number of correct answers
  Future<int> verifyAnswers(List<String> answers) async {
    final json = await _storage.read(key: _keyQuestions);
    if (json == null) return 0;
    final stored = (jsonDecode(json) as List).cast<Map<String, dynamic>>();

    int correct = 0;
    for (int i = 0; i < min(answers.length, stored.length); i++) {
      final hash = _hashAnswer(answers[i], stored[i]['salt'] as String);
      if (hash == stored[i]['hash']) correct++;
    }
    return correct;
  }

  bool get hasQuestions => _cachedHasQuestions;
  bool _cachedHasQuestions = false;

  Future<bool> checkHasQuestions() async {
    final json = await _storage.read(key: _keyQuestions);
    _cachedHasQuestions = json != null;
    return _cachedHasQuestions;
  }

  // ================================================================
  // Location Registration
  // ================================================================

  /// Register a trusted location (home, work, etc.)
  /// Stores only hashed grid coordinates — never exact location
  Future<void> registerLocation(String label) async {
    final position = await _getCurrentPosition();
    final locations = await _getLocations();

    if (locations.length >= maxLocations) {
      throw Exception('Maximum $maxLocations locations registered');
    }

    // Check for duplicate (same grid)
    final gridLat = _toGrid(position.latitude);
    final gridLng = _toGrid(position.longitude);
    final hash = _hashLocation(gridLat, gridLng);

    if (locations.any((loc) => loc['hash'] == hash)) {
      throw Exception('This location is already registered');
    }

    locations.add({
      'label': label,
      'hash': hash,
      'registeredAt': DateTime.now().toIso8601String(),
    });

    await _storage.write(key: _keyLocations, value: jsonEncode(locations));
  }

  /// Verify current location matches any registered location
  /// Checks exact grid + 8 neighboring grids (±1 grid cell ≈ 200m tolerance)
  Future<bool> verifyLocation() async {
    final locations = await _getLocations();
    if (locations.isEmpty) return false;

    final position = await _getCurrentPosition();
    final gridLat = _toGrid(position.latitude);
    final gridLng = _toGrid(position.longitude);

    // Check exact + 8 neighbors
    final gridStep = 1.0 / pow(10, gridPrecision);
    for (double dLat = -gridStep; dLat <= gridStep; dLat += gridStep) {
      for (double dLng = -gridStep; dLng <= gridStep; dLng += gridStep) {
        final testLat = _toGrid(gridLat + dLat);
        final testLng = _toGrid(gridLng + dLng);
        final testHash = _hashLocation(testLat, testLng);
        if (locations.any((loc) => loc['hash'] == testHash)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Get registered location labels (no coordinates)
  Future<List<Map<String, String>>> getLocationLabels() async {
    final locations = await _getLocations();
    return locations.map((loc) => {
      'label': loc['label'] as String,
      'registeredAt': loc['registeredAt'] as String,
    }).toList();
  }

  /// Remove a registered location by index
  Future<void> removeLocation(int index) async {
    final locations = await _getLocations();
    if (index < 0 || index >= locations.length) return;
    locations.removeAt(index);
    await _storage.write(key: _keyLocations, value: jsonEncode(locations));
  }

  Future<bool> hasLocations() async {
    final locations = await _getLocations();
    return locations.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> _getLocations() async {
    final json = await _storage.read(key: _keyLocations);
    if (json == null) return [];
    return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
  }

  // ================================================================
  // Recovery PIN (backup for when GPS is unavailable)
  // ================================================================

  Future<void> setRecoveryPin(String pin) async {
    if (pin.length < 6 || pin.length > 8) {
      throw Exception('Recovery PIN must be 6-8 digits');
    }
    final salt = _generateSalt();
    final hash = _hashAnswer(pin, salt);
    await _storage.write(
      key: _keyRecoveryPin,
      value: jsonEncode({'salt': salt, 'hash': hash}),
    );
  }

  Future<bool> verifyRecoveryPin(String pin) async {
    final json = await _storage.read(key: _keyRecoveryPin);
    if (json == null) return false;
    final stored = jsonDecode(json) as Map<String, dynamic>;
    final hash = _hashAnswer(pin, stored['salt'] as String);
    return hash == stored['hash'];
  }

  Future<bool> hasRecoveryPin() async {
    return await _storage.read(key: _keyRecoveryPin) != null;
  }

  // ================================================================
  // Full Recovery Flow
  // ================================================================

  /// Attempt recovery: questions + location (or recovery PIN as fallback)
  /// Returns: { success, reason, securityLevel }
  Future<Map<String, dynamic>> attemptRecovery({
    required List<String> answers,
    bool useLocation = true,
    String? recoveryPin,
  }) async {
    // Rate limiting check
    final rateLimitResult = await _checkRateLimit();
    if (!rateLimitResult['allowed']) {
      return {
        'success': false,
        'reason': 'Too many attempts. Try again in ${rateLimitResult['remainingMinutes']} minutes.',
        'locked': true,
      };
    }

    // Step 1: Verify security questions (need 3+ correct)
    final correctAnswers = await verifyAnswers(answers);
    final questions = await getQuestions();
    final minRequired = (questions.length * 0.6).ceil(); // 60% must be correct

    if (correctAnswers < minRequired) {
      await _recordAttempt(false);
      return {
        'success': false,
        'reason': 'Incorrect answers ($correctAnswers/${questions.length} correct, need $minRequired)',
        'correctAnswers': correctAnswers,
      };
    }

    // Step 2: Verify location OR recovery PIN
    bool locationVerified = false;
    if (useLocation) {
      try {
        locationVerified = await verifyLocation();
      } catch (_) {
        // GPS unavailable — fall through to PIN
      }
    }

    bool pinVerified = false;
    if (!locationVerified && recoveryPin != null) {
      pinVerified = await verifyRecoveryPin(recoveryPin);
    }

    if (!locationVerified && !pinVerified) {
      await _recordAttempt(false);
      return {
        'success': false,
        'reason': recoveryPin != null
            ? 'Recovery PIN incorrect'
            : 'Location mismatch. Use Recovery PIN as backup.',
        'correctAnswers': correctAnswers,
        'needsPin': true,
      };
    }

    // Success!
    await _recordAttempt(true);
    return {
      'success': true,
      'correctAnswers': correctAnswers,
      'locationVerified': locationVerified,
      'pinVerified': pinVerified,
    };
  }

  // ================================================================
  // Identity Status
  // ================================================================

  /// Get current identity protection level (0-3)
  Future<Map<String, dynamic>> getStatus() async {
    final hasQ = await checkHasQuestions();
    final hasL = await hasLocations();
    final hasP = await hasRecoveryPin();

    int level = 0;
    if (hasQ) level++;
    if (hasL) level++;
    if (hasP) level++;

    return {
      'level': level,
      'hasQuestions': hasQ,
      'hasLocations': hasL,
      'hasRecoveryPin': hasP,
    };
  }

  // ================================================================
  // Rate Limiting
  // ================================================================

  Future<Map<String, dynamic>> _checkRateLimit() async {
    final json = await _storage.read(key: _keyAttempts);
    if (json == null) return {'allowed': true};

    final data = jsonDecode(json) as Map<String, dynamic>;
    final attempts = data['count'] as int? ?? 0;
    final lastAttempt = DateTime.tryParse(data['lastAttempt'] as String? ?? '');

    if (lastAttempt == null) return {'allowed': true};

    final elapsed = DateTime.now().difference(lastAttempt);
    if (attempts >= maxAttempts && elapsed.inMinutes < lockoutMinutes) {
      return {
        'allowed': false,
        'remainingMinutes': lockoutMinutes - elapsed.inMinutes,
      };
    }

    // Reset if lockout expired
    if (elapsed.inMinutes >= lockoutMinutes) {
      await _storage.delete(key: _keyAttempts);
      return {'allowed': true};
    }

    return {'allowed': true};
  }

  Future<void> _recordAttempt(bool success) async {
    if (success) {
      await _storage.delete(key: _keyAttempts);
      return;
    }

    final json = await _storage.read(key: _keyAttempts);
    int count = 1;
    if (json != null) {
      final data = jsonDecode(json) as Map<String, dynamic>;
      count = (data['count'] as int? ?? 0) + 1;
    }

    await _storage.write(
      key: _keyAttempts,
      value: jsonEncode({
        'count': count,
        'lastAttempt': DateTime.now().toIso8601String(),
      }),
    );
  }

  // ================================================================
  // Delete all identity data
  // ================================================================

  Future<void> deleteAll() async {
    await _storage.delete(key: _keyQuestions);
    await _storage.delete(key: _keyLocations);
    await _storage.delete(key: _keyRecoveryPin);
    await _storage.delete(key: _keyAttempts);
  }

  // ================================================================
  // Helpers
  // ================================================================

  /// Hash answer with iterated SHA-256 (10,000 rounds)
  String _hashAnswer(String answer, String salt) {
    final normalized = answer.trim().toLowerCase();
    Uint8List bytes = Uint8List.fromList(utf8.encode('tpix-identity:$salt:$normalized'));
    for (int i = 0; i < 10000; i++) {
      bytes = Uint8List.fromList(sha256.convert(bytes).bytes);
    }
    return base64Encode(bytes);
  }

  /// Round coordinate to grid
  double _toGrid(double coord) {
    final factor = pow(10, gridPrecision);
    return (coord * factor).roundToDouble() / factor;
  }

  /// Hash grid coordinates
  String _hashLocation(double gridLat, double gridLng) {
    final input = 'tpix-loc:$gridLat:$gridLng';
    final bytes = sha256.convert(utf8.encode(input)).bytes;
    return base64Encode(bytes);
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Get current GPS position with permission handling
  Future<Position> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied. Enable in Settings.');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }
}
