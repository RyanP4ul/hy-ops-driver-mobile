import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../core/icons.dart';
import '../../core/palette.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/driver_ui.dart';
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
      await AppScope.of(
        context,
      ).login(_email.text.trim(), _password.text, remember: _remember);
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
  Widget build(BuildContext context) {
    final c = HyOpsColors.of(context);
    final scope = AppScope.of(context);
    final combinedError = _error ?? scope.error;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Panel(
                padding: const EdgeInsets.all(24),
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
                        const WorkspaceHeading(
                          'Driver sign in',
                          subtitle:
                              'Use the account provided by your HYOps dispatch.',
                        ),
                        const SizedBox(height: 24),
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
                            prefixIcon: Icon(Ic.mail, size: 18),
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
                            prefixIcon: const Icon(Ic.lock, size: 18),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure ? Ic.eye : Ic.eyeOff,
                                size: 18,
                              ),
                            ),
                          ),
                          onFieldSubmitted: (_) {
                            if (!_busy) _submit();
                          },
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            'Keep me signed in',
                            style: T.bodyBoldFor(c),
                          ),
                          subtitle: Text(
                            'Required to record deliveries while offline.',
                            style: T.smallFor(c),
                          ),
                          value: _remember,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _remember = v ?? false),
                        ),
                        if (combinedError != null) ...[
                          const SizedBox(height: 8),
                          FeedbackStrip(
                            combinedError,
                            action: scope.restorePending
                                ? TextButton(
                                    onPressed: _busy ? null : scope.initialize,
                                    child: const Text('Retry'),
                                  )
                                : null,
                          ),
                        ] else if (scope.restorePending) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : scope.initialize,
                            icon: const Icon(Ic.refresh, size: 16),
                            label: const Text('Retry saved session'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        BigButton(
                          _busy ? 'Signing in...' : 'Sign in',
                          busy: _busy,
                          onTap: _busy ? null : _submit,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Need access or a password reset? Contact your staff.',
                          textAlign: TextAlign.center,
                          style: T.smallFor(c),
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
