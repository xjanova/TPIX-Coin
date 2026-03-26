import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../services/identity_service.dart';
import '../services/synth_service.dart';

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> with TickerProviderStateMixin {
  final _identityService = IdentityService();
  Map<String, dynamic> _status = {};
  List<Map<String, String>> _locationLabels = [];
  bool _isLoading = true;

  late AnimationController _shieldController;
  late AnimationController _pulseController;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _progressController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _loadStatus();
  }

  @override
  void dispose() {
    _shieldController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    final status = await _identityService.getStatus();
    final locations = await _identityService.getLocationLabels();
    setState(() {
      _status = status;
      _locationLabels = locations;
      _isLoading = false;
    });
    _progressController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.8,
            colors: [Color(0xFF0F1B2D), Color(0xFF070B14)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      _buildHeader(l),
                      const SizedBox(height: 28),
                      _buildShieldHero(l),
                      const SizedBox(height: 28),
                      _buildStepCards(l),
                      const SizedBox(height: 24),
                      if ((_status['level'] as int? ?? 0) >= 2)
                        _buildRecoveryTestButton(l),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // ================================================================
  // Header
  // ================================================================

  Widget _buildHeader(LocaleProvider l) {
    return Row(
      children: [
        GestureDetector(
          onTap: () { SynthService.playTap(); Navigator.pop(context); },
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppTheme.primary.withValues(alpha: 0.15), AppTheme.accent.withValues(alpha: 0.08)],
              ),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: AppTheme.primary, size: 20),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.accent],
                ).createShader(bounds),
                child: Text(
                  l.t('identity.title'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              Text(l.t('identity.subtitle'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ],
          ),
        ),
      ],
    );
  }

  // ================================================================
  // Shield Hero — animated level indicator
  // ================================================================

  Widget _buildShieldHero(LocaleProvider l) {
    final level = _status['level'] as int? ?? 0;
    final colors = [
      [const Color(0xFFFF4444), const Color(0xFFFF1744)],
      [const Color(0xFFFFA726), const Color(0xFFF57C00)],
      [const Color(0xFF7C4DFF), const Color(0xFF651FFF)],
      [const Color(0xFF00E676), const Color(0xFF00C853)],
    ];
    final levelColors = colors[level.clamp(0, 3)];
    final labels = [l.t('identity.level0'), l.t('identity.level1'), l.t('identity.level2'), l.t('identity.level3')];

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        final pulse = 0.95 + (_pulseController.value * 0.05);
        return Transform.scale(
          scale: level == 3 ? pulse : 1.0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  levelColors[0].withValues(alpha: 0.12),
                  levelColors[1].withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(color: levelColors[0].withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: levelColors[0].withValues(alpha: level == 3 ? 0.15 : 0.08),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Animated shield
                SizedBox(
                  width: 90, height: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotating ring
                      AnimatedBuilder(
                        animation: _shieldController,
                        builder: (_, __) => Transform.rotate(
                          angle: _shieldController.value * 2 * pi,
                          child: CustomPaint(
                            size: const Size(90, 90),
                            painter: _ShieldRingPainter(
                              color: levelColors[0],
                              progress: level / 3,
                            ),
                          ),
                        ),
                      ),
                      // Level number
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: levelColors),
                          boxShadow: [
                            BoxShadow(color: levelColors[0].withValues(alpha: 0.4), blurRadius: 16),
                          ],
                        ),
                        child: Center(
                          child: level == 3
                              ? const Icon(Icons.verified_rounded, color: Colors.white, size: 30)
                              : Text('$level', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.t('identity.securityLevel'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[level.clamp(0, 3)],
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: levelColors[0]),
                ),
                const SizedBox(height: 16),
                // Step indicators
                AnimatedBuilder(
                  animation: _progressController,
                  builder: (_, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStepDot(0, level, levelColors[0]),
                      _buildStepLine(0, level, levelColors[0]),
                      _buildStepDot(1, level, levelColors[0]),
                      _buildStepLine(1, level, levelColors[0]),
                      _buildStepDot(2, level, levelColors[0]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepDot(int step, int level, Color color) {
    final active = step < level;
    final animValue = _progressController.value;
    final dotScale = active ? (animValue > (step * 0.3) ? 1.0 : 0.5) : 0.5;

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + step * 100),
      width: 12, height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : Colors.white.withValues(alpha: 0.15),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1),
          width: 2,
        ),
        boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)] : [],
      ),
      transform: Matrix4.identity()..scale(dotScale, dotScale, 1.0),
    );
  }

  Widget _buildStepLine(int step, int level, Color color) {
    final active = step < level;
    return Container(
      width: 40, height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(1),
        color: active ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
      ),
    );
  }

  // ================================================================
  // Step Cards — 3 setup items with beautiful styling
  // ================================================================

  Widget _buildStepCards(LocaleProvider l) {
    final hasQ = _status['hasQuestions'] as bool? ?? false;
    final hasL = _status['hasLocations'] as bool? ?? false;
    final hasP = _status['hasRecoveryPin'] as bool? ?? false;

    return Column(
      children: [
        _buildStepCard(
          step: 1,
          icon: Icons.psychology_rounded,
          title: l.t('identity.questions'),
          description: l.t('identity.questionsDesc'),
          isComplete: hasQ,
          gradientColors: const [Color(0xFF06B6D4), Color(0xFF0891B2)],
          onTap: () => _showSecurityQuestionsDialog(l),
        ),
        const SizedBox(height: 14),
        _buildStepCard(
          step: 2,
          icon: Icons.share_location_rounded,
          title: l.t('identity.location'),
          description: l.t('identity.locationDesc'),
          isComplete: hasL,
          gradientColors: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
          onTap: () => _showLocationDialog(l),
          extraContent: _locationLabels.isNotEmpty ? _buildLocationChips() : null,
        ),
        const SizedBox(height: 14),
        _buildStepCard(
          step: 3,
          icon: Icons.fiber_pin_rounded,
          title: l.t('identity.recoveryPin'),
          description: l.t('identity.recoveryPinDesc'),
          isComplete: hasP,
          gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
          onTap: () => _showRecoveryPinDialog(l),
        ),
      ],
    );
  }

  Widget _buildStepCard({
    required int step,
    required IconData icon,
    required String title,
    required String description,
    required bool isComplete,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    Widget? extraContent,
  }) {
    return GestureDetector(
      onTap: () { SynthService.playTap(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradientColors[0].withValues(alpha: isComplete ? 0.12 : 0.06),
              gradientColors[1].withValues(alpha: 0.02),
            ],
          ),
          border: Border.all(
            color: isComplete
                ? gradientColors[0].withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Gradient icon circle
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isComplete
                        ? LinearGradient(colors: gradientColors)
                        : null,
                    color: isComplete ? null : Colors.white.withValues(alpha: 0.06),
                    boxShadow: isComplete
                        ? [BoxShadow(color: gradientColors[0].withValues(alpha: 0.3), blurRadius: 12)]
                        : [],
                  ),
                  child: Icon(
                    icon,
                    color: isComplete ? Colors.white : AppTheme.textMuted,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: gradientColors[0].withValues(alpha: 0.15),
                            ),
                            child: Text(
                              'STEP $step',
                              style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w800,
                                color: gradientColors[0], letterSpacing: 1,
                              ),
                            ),
                          ),
                          if (isComplete) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle_rounded, color: gradientColors[0], size: 16),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: isComplete ? gradientColors[0] : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(description, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                Icon(
                  isComplete ? Icons.settings_rounded : Icons.arrow_forward_ios_rounded,
                  color: isComplete ? gradientColors[0].withValues(alpha: 0.5) : AppTheme.textMuted.withValues(alpha: 0.5),
                  size: isComplete ? 20 : 14,
                ),
              ],
            ),
            if (extraContent != null) ...[
              const SizedBox(height: 12),
              extraContent,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _locationLabels.asMap().entries.map((entry) {
        final idx = entry.key;
        final loc = entry.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppTheme.accent.withValues(alpha: 0.1),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.pin_drop_rounded, size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(loc['label'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF0D1321),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Remove Location?', style: TextStyle(color: Colors.white, fontSize: 16)),
                      content: Text('Remove "${loc['label']}"?', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted))),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: AppTheme.danger))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _identityService.removeLocation(idx);
                    await _loadStatus();
                    SynthService.playTap();
                  }
                },
                child: Icon(Icons.close_rounded, size: 14, color: AppTheme.accent.withValues(alpha: 0.5)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ================================================================
  // Recovery Test Button
  // ================================================================

  Widget _buildRecoveryTestButton(LocaleProvider l) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: AppTheme.brandGradient,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppTheme.bgDark,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () { SynthService.playTap(); _showRecoveryTestDialog(l); },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => AppTheme.brandGradient.createShader(bounds),
                    child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  ShaderMask(
                    shaderCallback: (bounds) => AppTheme.brandGradient.createShader(bounds),
                    child: Text(
                      l.t('identity.testRecovery'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // Dialogs — same logic, better bottom sheet styling
  // ================================================================

  Widget _sheetHandle() => Center(
    child: Container(
      width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  InputDecoration _inputDeco({required String hint, IconData? prefix}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5), fontSize: 14),
    prefixIcon: prefix != null ? Icon(prefix, color: AppTheme.textMuted, size: 20) : null,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.04),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  void _showSecurityQuestionsDialog(LocaleProvider l) {
    final controllers = List.generate(3, (_) => [TextEditingController(), TextEditingController()]);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          top: 16, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0D1321),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                    ),
                    child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('identity.questions'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(l.t('identity.questionsHint'), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...List.generate(3, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.t('identity.questionLabel')} ${i + 1}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary.withValues(alpha: 0.7), letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: controllers[i][0],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDeco(hint: l.t('identity.questionPlaceholder'), prefix: Icons.help_outline_rounded),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controllers[i][1],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDeco(hint: l.t('identity.answerPlaceholder'), prefix: Icons.key_rounded),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              _buildGradientButton(
                label: l.t('identity.save'),
                icon: Icons.save_rounded,
                colors: const [Color(0xFF06B6D4), Color(0xFF0891B2)],
                onTap: () async {
                  final pairs = controllers.map((c) => {
                    'question': c[0].text.trim(),
                    'answer': c[1].text.trim(),
                  }).where((qa) => qa['question']!.isNotEmpty && qa['answer']!.isNotEmpty).toList();

                  if (pairs.length < 3) {
                    _showSnack(l.t('identity.needQuestions'), AppTheme.danger);
                    return;
                  }

                  try {
                    await _identityService.setSecurityQuestions(pairs);
                    SynthService.playSendSuccess();
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSnack(l.t('identity.questionsSaved'), AppTheme.success);
                    await _loadStatus();
                  } catch (e) {
                    _showSnack(e.toString(), AppTheme.danger);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLocationDialog(LocaleProvider l) {
    final labelController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          top: 16, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0D1321),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)]),
                  ),
                  child: const Icon(Icons.share_location_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('identity.location'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(l.t('identity.locationHint'), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Privacy badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.success.withValues(alpha: 0.08),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: AppTheme.success.withValues(alpha: 0.8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.isThai ? 'เก็บเฉพาะ hash เท่านั้น ไม่เก็บพิกัดจริง' : 'Only stores hash — never your exact coordinates',
                      style: TextStyle(fontSize: 11, color: AppTheme.success.withValues(alpha: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: labelController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDeco(hint: l.t('identity.locationLabel'), prefix: Icons.label_outline_rounded),
            ),
            const SizedBox(height: 16),
            _LocationRegisterButton(
              labelController: labelController,
              identityService: _identityService,
              l: l,
              colors: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
              onSuccess: () async {
                SynthService.playSendSuccess();
                if (ctx.mounted) Navigator.pop(ctx);
                _showSnack(l.t('identity.locationSaved'), AppTheme.success);
                await _loadStatus();
              },
              onError: (e) => _showSnack(e, AppTheme.danger),
              buildButton: _buildGradientButton,
            ),
          ],
        ),
      ),
    );
  }

  void _showRecoveryPinDialog(LocaleProvider l) {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          top: 16, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF0D1321),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                  ),
                  child: const Icon(Icons.fiber_pin_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('identity.recoveryPin'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text(l.t('identity.recoveryPinHint'), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '------',
                hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.3), letterSpacing: 10),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.warm, width: 1.5)),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: l.t('identity.confirmPin'),
                hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.3), letterSpacing: 1),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.warm, width: 1.5)),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            _buildGradientButton(
              label: l.t('identity.save'),
              icon: Icons.save_rounded,
              colors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
              onTap: () async {
                final pin = pinController.text.trim();
                final confirm = confirmController.text.trim();

                if (pin.length < 6) {
                  _showSnack(l.t('identity.pinTooShort'), AppTheme.danger);
                  return;
                }
                if (pin != confirm) {
                  _showSnack(l.t('identity.pinMismatch'), AppTheme.danger);
                  return;
                }

                try {
                  await _identityService.setRecoveryPin(pin);
                  SynthService.playSendSuccess();
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showSnack(l.t('identity.pinSaved'), AppTheme.success);
                  await _loadStatus();
                } catch (e) {
                  _showSnack(e.toString(), AppTheme.danger);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRecoveryTestDialog(LocaleProvider l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1321),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => AppTheme.brandGradient.createShader(bounds),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 10),
            Text(l.t('identity.testRecovery'), style: const TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(l.t('identity.testRecoveryDesc'), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: AppTheme.brandGradient,
            ),
            child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); _runRecoveryTest(l); },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: Text(l.t('identity.startTest'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _runRecoveryTest(LocaleProvider l) async {
    final questions = await _identityService.getQuestions();
    if (questions.isEmpty || !mounted) return;

    final answerControllers = List.generate(questions.length, (_) => TextEditingController());
    final pinController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          top: 16, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        decoration: const BoxDecoration(
          color: Color(0xFF0D1321),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sheetHandle(),
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => AppTheme.brandGradient.createShader(bounds),
                    child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Text(l.t('identity.testRecovery'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
              const SizedBox(height: 20),

              ...List.generate(questions.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(questions[i], style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: answerControllers[i],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _inputDeco(hint: l.t('identity.answerPlaceholder'), prefix: Icons.key_rounded),
                    ),
                  ],
                ),
              )),

              Text(l.t('identity.recoveryPinOptional'), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Recovery PIN',
                  hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.warm, width: 1.5)),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              _RecoveryTestButton(
                answerControllers: answerControllers,
                pinController: pinController,
                identityService: _identityService,
                l: l,
                buildButton: _buildGradientButton,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // Shared UI Components
  // ================================================================

  Widget _buildGradientButton({
    required String label,
    IconData? icon,
    required List<Color> colors,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: colors),
        boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ElevatedButton.icon(
          onPressed: isLoading ? null : onTap,
          icon: isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppTheme.success ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white, size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ================================================================
// Extracted StatefulWidgets (proper state management)
// ================================================================

class _LocationRegisterButton extends StatefulWidget {
  final TextEditingController labelController;
  final IdentityService identityService;
  final LocaleProvider l;
  final List<Color> colors;
  final VoidCallback onSuccess;
  final void Function(String) onError;
  final Widget Function({required String label, IconData? icon, required List<Color> colors, required VoidCallback onTap, bool isLoading}) buildButton;

  const _LocationRegisterButton({
    required this.labelController,
    required this.identityService,
    required this.l,
    required this.colors,
    required this.onSuccess,
    required this.onError,
    required this.buildButton,
  });

  @override
  State<_LocationRegisterButton> createState() => _LocationRegisterButtonState();
}

class _LocationRegisterButtonState extends State<_LocationRegisterButton> {
  bool _registering = false;

  @override
  Widget build(BuildContext context) {
    return widget.buildButton(
      label: widget.l.t('identity.registerHere'),
      icon: Icons.my_location_rounded,
      colors: widget.colors,
      isLoading: _registering,
      onTap: () async {
        final label = widget.labelController.text.trim();
        if (label.isEmpty) {
          widget.onError(widget.l.t('identity.needLabel'));
          return;
        }
        setState(() => _registering = true);
        try {
          await widget.identityService.registerLocation(label);
          widget.onSuccess();
        } catch (e) {
          widget.onError(e.toString());
        } finally {
          if (mounted) setState(() => _registering = false);
        }
      },
    );
  }
}

class _RecoveryTestButton extends StatefulWidget {
  final List<TextEditingController> answerControllers;
  final TextEditingController pinController;
  final IdentityService identityService;
  final LocaleProvider l;
  final Widget Function({required String label, IconData? icon, required List<Color> colors, required VoidCallback onTap, bool isLoading}) buildButton;

  const _RecoveryTestButton({
    required this.answerControllers,
    required this.pinController,
    required this.identityService,
    required this.l,
    required this.buildButton,
  });

  @override
  State<_RecoveryTestButton> createState() => _RecoveryTestButtonState();
}

class _RecoveryTestButtonState extends State<_RecoveryTestButton> {
  bool _testing = false;
  String? _resultText;
  Color? _resultColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        widget.buildButton(
          label: widget.l.t('identity.verify'),
          icon: Icons.fingerprint_rounded,
          isLoading: _testing,
          colors: const [Color(0xFF06B6D4), Color(0xFF8B5CF6)],
          onTap: () async {
            setState(() { _testing = true; _resultText = null; });

            final answers = widget.answerControllers.map((c) => c.text).toList();
            final pin = widget.pinController.text.trim().isNotEmpty ? widget.pinController.text.trim() : null;

            final result = await widget.identityService.attemptRecovery(answers: answers, recoveryPin: pin);

            if (!mounted) return;

            if (result['success'] == true) {
              SynthService.playSendSuccess();
              setState(() {
                _testing = false;
                _resultText = widget.l.t('identity.testSuccess');
                _resultColor = AppTheme.success;
              });
            } else {
              SynthService.playError();
              setState(() {
                _testing = false;
                _resultText = result['reason'] as String? ?? widget.l.t('identity.testFailed');
                _resultColor = AppTheme.danger;
              });
            }
          },
        ),
        if (_resultText != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _resultColor!.withValues(alpha: 0.08),
              border: Border.all(color: _resultColor!.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  _resultColor == AppTheme.success ? Icons.celebration_rounded : Icons.error_outline_rounded,
                  color: _resultColor, size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_resultText!, style: TextStyle(fontSize: 13, color: _resultColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ================================================================
// Custom Painters
// ================================================================

class _ShieldRingPainter extends CustomPainter {
  final Color color;
  final double progress;

  _ShieldRingPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background ring
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0.0), color, color.withValues(alpha: 0.3)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      progressPaint,
    );

    // Glowing dot at current position
    final dotAngle = -pi / 2 + 2 * pi * progress;
    final dotX = center.dx + radius * cos(dotAngle);
    final dotY = center.dy + radius * sin(dotAngle);
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(dotX, dotY), 4, dotPaint);

    // Glow
    final glowPaint = Paint()..color = color.withValues(alpha: 0.3);
    canvas.drawCircle(Offset(dotX, dotY), 8, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _ShieldRingPainter oldDelegate) =>
      color != oldDelegate.color || progress != oldDelegate.progress;
}
