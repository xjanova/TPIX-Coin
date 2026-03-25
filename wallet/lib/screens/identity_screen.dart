import 'package:flutter/material.dart';
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

class _IdentityScreenState extends State<IdentityScreen> {
  final _identityService = IdentityService();
  Map<String, dynamic> _status = {};
  List<Map<String, String>> _locationLabels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
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
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.5,
            colors: [Color(0xFF0C1929), AppTheme.bgDark],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(l),
                      const SizedBox(height: 20),
                      _buildSecurityLevel(l),
                      const SizedBox(height: 24),
                      _buildQuestionCard(l),
                      const SizedBox(height: 16),
                      _buildLocationCard(l),
                      const SizedBox(height: 16),
                      _buildRecoveryPinCard(l),
                      const SizedBox(height: 24),
                      if ((_status['level'] as int? ?? 0) >= 2)
                        _buildRecoveryTestButton(l),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(LocaleProvider l) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withValues(alpha: 0.1),
            ),
            child: const Icon(Icons.arrow_back, color: AppTheme.primary, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('identity.title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            Text(l.t('identity.subtitle'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
      ],
    );
  }

  Widget _buildSecurityLevel(LocaleProvider l) {
    final level = _status['level'] as int? ?? 0;
    final colors = [AppTheme.danger, AppTheme.warm, AppTheme.accent, AppTheme.success];
    final labels = [
      l.t('identity.level0'),
      l.t('identity.level1'),
      l.t('identity.level2'),
      l.t('identity.level3'),
    ];
    final color = colors[level.clamp(0, 3)];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
            ),
            child: Center(
              child: Text(
                '$level',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('identity.securityLevel'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                Text(labels[level.clamp(0, 3)], style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 4),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: level / 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: color,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(LocaleProvider l) {
    final hasQ = _status['hasQuestions'] as bool? ?? false;
    return _buildSetupCard(
      icon: Icons.quiz_rounded,
      title: l.t('identity.questions'),
      description: l.t('identity.questionsDesc'),
      isSetup: hasQ,
      color: AppTheme.primary,
      onTap: () => _showSecurityQuestionsDialog(l),
    );
  }

  Widget _buildLocationCard(LocaleProvider l) {
    final hasL = _status['hasLocations'] as bool? ?? false;
    return Column(
      children: [
        _buildSetupCard(
          icon: Icons.location_on_rounded,
          title: l.t('identity.location'),
          description: l.t('identity.locationDesc'),
          isSetup: hasL,
          color: AppTheme.accent,
          onTap: () => _showLocationDialog(l),
        ),
        if (_locationLabels.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._locationLabels.asMap().entries.map((entry) {
            final idx = entry.key;
            final loc = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppTheme.accent.withValues(alpha: 0.06),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pin_drop, size: 16, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc['label'] ?? '',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await _identityService.removeLocation(idx);
                        await _loadStatus();
                        SynthService.playTap();
                      },
                      child: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildRecoveryPinCard(LocaleProvider l) {
    final hasP = _status['hasRecoveryPin'] as bool? ?? false;
    return _buildSetupCard(
      icon: Icons.pin_rounded,
      title: l.t('identity.recoveryPin'),
      description: l.t('identity.recoveryPinDesc'),
      isSetup: hasP,
      color: AppTheme.warm,
      onTap: () => _showRecoveryPinDialog(l),
    );
  }

  Widget _buildSetupCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isSetup,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: 0.06),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
                  const SizedBox(height: 2),
                  Text(description, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ),
            Icon(
              isSetup ? Icons.check_circle : Icons.arrow_forward_ios,
              color: isSetup ? AppTheme.success : AppTheme.textMuted,
              size: isSetup ? 24 : 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryTestButton(LocaleProvider l) {
    return Center(
      child: TextButton.icon(
        onPressed: () => _showRecoveryTestDialog(l),
        icon: const Icon(Icons.verified_user, size: 18),
        label: Text(l.t('identity.testRecovery')),
        style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
      ),
    );
  }

  // ================================================================
  // Dialogs
  // ================================================================

  void _showSecurityQuestionsDialog(LocaleProvider l) {
    final controllers = List.generate(3, (_) => [TextEditingController(), TextEditingController()]);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          top: 20, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.bgDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.textMuted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.t('identity.questions'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(l.t('identity.questionsHint'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              ...List.generate(3, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.t('identity.questionLabel')} ${i + 1}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: controllers[i][0],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: l.t('identity.questionPlaceholder'),
                        hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: controllers[i][1],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: l.t('identity.answerPlaceholder'),
                        hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(l.t('identity.save')),
                ),
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
          top: 20, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.bgDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.textMuted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.t('identity.location'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 4),
            Text(l.t('identity.locationHint'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            TextField(
              controller: labelController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: l.t('identity.locationLabel'),
                hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.label_outline, color: AppTheme.textMuted, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: StatefulBuilder(
                builder: (context, setButtonState) {
                  bool registering = false;
                  return ElevatedButton.icon(
                    onPressed: registering ? null : () async {
                      final label = labelController.text.trim();
                      if (label.isEmpty) {
                        _showSnack(l.t('identity.needLabel'), AppTheme.danger);
                        return;
                      }
                      setButtonState(() => registering = true);
                      try {
                        await _identityService.registerLocation(label);
                        SynthService.playSendSuccess();
                        if (ctx.mounted) Navigator.pop(ctx);
                        _showSnack(l.t('identity.locationSaved'), AppTheme.success);
                        await _loadStatus();
                      } catch (e) {
                        _showSnack(e.toString(), AppTheme.danger);
                      } finally {
                        if (ctx.mounted) setButtonState(() => registering = false);
                      }
                    },
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(l.t('identity.registerHere')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  );
                },
              ),
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
          top: 20, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: AppTheme.bgDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.textMuted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.t('identity.recoveryPin'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 4),
            Text(l.t('identity.recoveryPinHint'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '6-8 digits',
                hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5), letterSpacing: 1),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: l.t('identity.confirmPin'),
                hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5), letterSpacing: 1),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warm,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(l.t('identity.save')),
              ),
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
        backgroundColor: AppTheme.bgDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l.t('identity.testRecovery'), style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Text(l.t('identity.testRecoveryDesc'), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.t('wallets.cancel'), style: const TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _runRecoveryTest(l);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text(l.t('identity.startTest'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _runRecoveryTest(LocaleProvider l) async {
    // Get questions and show answer dialog
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
          top: 20, left: 20, right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        decoration: const BoxDecoration(
          color: AppTheme.bgDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.textMuted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.t('identity.testRecovery'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 16),

              // Questions
              ...List.generate(questions.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(questions[i], style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: answerControllers[i],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: l.t('identity.answerPlaceholder'),
                        hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ],
                ),
              )),

              // Recovery PIN (backup)
              Text(l.t('identity.recoveryPinOptional'), style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 4),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Recovery PIN',
                  hintStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: StatefulBuilder(
                  builder: (context, setButtonState) {
                    bool testing = false;
                    String? resultText;
                    Color? resultColor;

                    return Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: testing ? null : () async {
                            setButtonState(() { testing = true; resultText = null; });

                            final answers = answerControllers.map((c) => c.text).toList();
                            final pin = pinController.text.trim().isNotEmpty ? pinController.text.trim() : null;

                            final result = await _identityService.attemptRecovery(
                              answers: answers,
                              recoveryPin: pin,
                            );

                            if (result['success'] == true) {
                              SynthService.playSendSuccess();
                              setButtonState(() {
                                testing = false;
                                resultText = l.t('identity.testSuccess');
                                resultColor = AppTheme.success;
                              });
                            } else {
                              SynthService.playError();
                              setButtonState(() {
                                testing = false;
                                resultText = result['reason'] as String? ?? l.t('identity.testFailed');
                                resultColor = AppTheme.danger;
                              });
                            }
                          },
                          icon: testing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.verified_user, size: 18),
                          label: Text(l.t('identity.verify')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size(double.infinity, 0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        if (resultText != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: resultColor!.withValues(alpha: 0.1),
                              border: Border.all(color: resultColor!.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  resultColor == AppTheme.success ? Icons.check_circle : Icons.error,
                                  color: resultColor, size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(resultText!, style: TextStyle(fontSize: 13, color: resultColor)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }
}
