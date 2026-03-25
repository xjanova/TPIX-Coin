import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/locale_provider.dart';
import '../core/theme.dart';
import '../providers/wallet_provider.dart';
import '../services/synth_service.dart';
import 'home_screen.dart';

class PinScreen extends StatefulWidget {
  final bool isSetup;
  const PinScreen({super.key, this.isSetup = false});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _confirmPin;
  bool _isConfirmMode = false;
  bool _isError = false;
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onNumberTap(String num) {
    if (_pin.length >= 6) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += num;
      _isError = false;
    });

    if (_pin.length == 6) {
      _handleComplete();
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _isError = false;
    });
  }

  void _handleComplete() async {
    if (widget.isSetup) {
      if (!_isConfirmMode) {
        _confirmPin = _pin;
        setState(() {
          _pin = '';
          _isConfirmMode = true;
        });
      } else {
        if (_pin == _confirmPin) {
          final provider = context.read<WalletProvider>();
          await provider.saveWallet(_pin);
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        } else {
          _showError();
        }
      }
    } else {
      // Unlock
      final provider = context.read<WalletProvider>();
      final success = await provider.unlock(_pin);
      if (success) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        _showError();
      }
    }
  }

  void _showError() {
    HapticFeedback.heavyImpact();
    SynthService.playError();
    setState(() {
      _isError = true;
      _pin = '';
    });
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<LocaleProvider>();
    final title = widget.isSetup
        ? (_isConfirmMode ? l.t('pin.confirm') : l.t('pin.setup'))
        : l.t('pin.unlock');
    final subtitle = widget.isSetup
        ? (_isConfirmMode ? l.t('pin.confirmSub') : l.t('pin.setupSub'))
        : l.t('pin.unlockSub');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.5),
            radius: 1.5,
            colors: [Color(0xFF0F172A), AppTheme.bgDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2), blurRadius: 30),
                  ],
                ),
                child: Image.asset('assets/images/tpixlogo.webp'),
              ),

              const SizedBox(height: 32),

              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(fontSize: 14, color: AppTheme.textMuted)),

              const SizedBox(height: 40),

              // PIN dots
              AnimatedBuilder(
                animation: _shakeController,
                builder: (_, child) {
                  final shake = sin(_shakeController.value * pi * 4) * 10;
                  return Transform.translate(offset: Offset(shake, 0), child: child);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < _pin.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: filled ? 18 : 14,
                      height: filled ? 18 : 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isError
                            ? AppTheme.danger
                            : filled
                                ? AppTheme.primary
                                : Colors.white.withValues(alpha: 0.1),
                        boxShadow: filled
                            ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 10)]
                            : null,
                        border: !filled
                            ? Border.all(color: Colors.white.withValues(alpha: 0.15))
                            : null,
                      ),
                    );
                  }),
                ),
              ),

              if (_isError)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(l.t('pin.wrong'), style: const TextStyle(color: AppTheme.danger, fontSize: 14)),
                ),

              const Spacer(flex: 2),

              // Number pad
              _buildNumberPad(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'DEL'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: keys.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) return const SizedBox(width: 72);
              if (key == 'DEL') {
                return _buildKeyButton(
                  child: const Icon(Icons.backspace_outlined, color: AppTheme.textSecondary, size: 24),
                  onTap: _onDelete,
                );
              }
              return _buildKeyButton(
                child: Text(key, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
                onTap: () => _onNumberTap(key),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeyButton({required Widget child, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(36),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
