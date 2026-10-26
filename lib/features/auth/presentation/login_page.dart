import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui.dart';
import '../../../core/widgets/submit_button.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(authControllerProvider.notifier).lastCompanyCode().then((code) {
      if (mounted && code != null && _company.text.isEmpty) _company.text = code;
    });
  }

  @override
  void dispose() {
    _company.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(companyCode: _company.text, emailOrMobile: _email.text, password: _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final expired = state is AuthSignedOut && state.expired;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: brandGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: const [
                                BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
                              ],
                            ),
                            child: const Icon(Icons.local_shipping_rounded, size: 46, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Courier Pro',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Book, load, dispatch and deliver',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 28),
                        Card(
                          elevation: 8,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Sign in with your branch account',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 16),
                                if (expired && _error == null)
                                  const _Banner(
                                    icon: Icons.lock_clock_outlined,
                                    color: AppColors.warning,
                                    text: 'Your session has expired. Please sign in again.',
                                  ),
                                if (_error != null)
                                  _Banner(icon: Icons.error_outline, color: AppColors.danger, text: _error!),
                                TextFormField(
                                  controller: _company,
                                  textCapitalization: TextCapitalization.characters,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Company code',
                                    hintText: 'e.g. ACME_LOGISTICS',
                                    prefixIcon: Icon(Icons.business_outlined),
                                  ),
                                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your company code' : null,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                                  decoration: const InputDecoration(
                                    labelText: 'Email or mobile number',
                                    prefixIcon: Icon(Icons.person_outline),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty) ? 'Enter your email or mobile number' : null,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _password,
                                  obscureText: _hidePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _hidePassword ? 'Show password' : 'Hide password',
                                      icon: Icon(
                                        _hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      ),
                                      onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                    ),
                                  ),
                                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                                ),
                                const SizedBox(height: 24),
                                SubmitButton(label: 'Sign in', onPressed: _submit),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}
