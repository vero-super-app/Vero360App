import 'package:flutter/material.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/GernalServices/changepassword_service.dart';
import 'package:vero360_app/utils/toasthelper.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final Color _brand = const Color(0xFFFF8A00);
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _svc = AccountService();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _saving = false;
  double _strength = 0.0;

  @override
  void initState() {
    super.initState();
    _newCtrl.addListener(_recalcStrength);
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.removeListener(_recalcStrength);
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _recalcStrength() {
    final s = _newCtrl.text;
    setState(() => _strength = _passwordStrength(s));
  }

  double _passwordStrength(String s) {
    if (s.isEmpty) return 0;
    int score = 0;
    if (s.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(s)) score++;
    if (RegExp(r'[a-z]').hasMatch(s)) score++;
    if (RegExp(r'\d').hasMatch(s)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(s)) score++;
    return (score / 5).clamp(0, 1).toDouble();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await _svc.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (!mounted) return;
      ToastHelper.showCustomToast(
        context,
        ' Password updated successfully',
        isSuccess: true,
        errorMessage: '',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final String message = e is ApiException
          ? e.message
          : 'Failed to change password';
      ToastHelper.showCustomToast(
        context,
        message,
        isSuccess: false,
        errorMessage: e is ApiException ? '' : e.toString(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _barColor(double v) {
    if (v < .34) return Colors.redAccent;
    if (v < .67) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF222222),
        );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF222222),
        title: const Text('Change password'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 22,
                  spreadRadius: -8,
                  offset: Offset(0, 14),
                  color: Color(0x1A000000),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_brand.withValues(alpha: .15), Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      size: 40, color: Color(0xFF6B778C)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Change password', style: titleStyle),
                      const SizedBox(height: 6),
                      Text(
                        'Use a strong, unique password you haven’t used elsewhere.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6B778C)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Form
          Form(
            key: _formKey,
            child: Column(
              children: [
                // Current
                TextFormField(
                  controller: _currentCtrl,
                  obscureText: !_showCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showCurrent
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showCurrent = !_showCurrent),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your current password' : null,
                ),
                const SizedBox(height: 14),

                // New
                TextFormField(
                  controller: _newCtrl,
                  obscureText: !_showNew,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showNew
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _showNew = !_showNew),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a new password';
                    if (v.length < 8) return 'Must be at least 8 characters';
                    if (!RegExp(r'[A-Z]').hasMatch(v)) {
                      return 'Add at least one uppercase letter';
                    }
                    if (!RegExp(r'\d').hasMatch(v)) {
                      return 'Add at least one number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Strength meter
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _strength,
                    minHeight: 8,
                    color: _barColor(_strength),
                    backgroundColor: Colors.black12,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _strength < .34
                        ? 'Weak'
                        : _strength < .67
                            ? 'Medium'
                            : 'Strong',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: _barColor(_strength)),
                  ),
                ),
                const SizedBox(height: 14),

                // Confirm
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: !_showConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showConfirm = !_showConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Re-enter the new password';
                    }
                    if (v != _newCtrl.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.black12.withValues(alpha: .4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.lock_outline),
                        label: Text(_saving ? 'Saving…' : 'Update password'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
