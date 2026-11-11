import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../core/palette.dart';
import '../../state/app_state.dart';
import '../../widgets/driver_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/workspace.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false, _busy = false, _seeded = false, _obscure = true;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_seeded) {
      _seeded = true;
      final saved = AppScope.of(context).rememberedUser;
      _email.text = saved ?? '';
      _remember = saved != null;
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context)
          .login(_email.text.trim(), _password.text, remember: _remember);
    } catch (e) {
      if (mounted) setState(() => _error = apiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: P.bg,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Panel(
              padding: const EdgeInsets.all(20),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: DriverBrand(),
                      ),
                      const SizedBox(height: 24),
                      const WorkspaceHeading('Driver sign in'),
                      const SizedBox(height: 10),
                      Text(
                        'Use the account provided by your HYOps staff.',
                        style: T.body.copyWith(color: P.muted),
                      ),
                      const SizedBox(height: 28),
                      if (AppScope.of(context).error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FeedbackStrip(AppScope.of(context).error!),
                        ),
                      if (AppScope.of(context).restorePending)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => AppScope.of(context).initialize(),
                            child: const Text('Retry saved session'),
                          ),
                        ),
                      TextFormField(
                        controller: _email,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your driver email.'
                            : null,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter your password.'
                            : null,
                        enabled: !_busy,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onFieldSubmitted: (_) {
                          if (!_busy) _submit();
                        },
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Keep me signed in'),
                        value: _remember,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _remember = v ?? false),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FeedbackStrip(_error!),
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Signing in...' : 'Sign in'),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Need access or a password reset? Contact your staff.',
                        textAlign: TextAlign.center,
                        style: T.small,
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
