import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth.dart' show authRepositoryProvider;

class ForgotPasswordScreen extends ConsumerStatefulWidget {
	const ForgotPasswordScreen({super.key});

	@override
	ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
	final _formKey = GlobalKey<FormState>();
	final _emailCtrl = TextEditingController();
	bool _loading = false;
	String? _message;
	String? _error;

	@override
	void dispose() {
		_emailCtrl.dispose();
		super.dispose();
	}

	Future<void> _submit() async {
		if (!_formKey.currentState!.validate()) return;
		setState(() { _loading = true; _error = null; _message = null; });
		final repo = ref.read(authRepositoryProvider);
		try {
			await repo.sendPasswordResetEmail(email: _emailCtrl.text.trim());
			setState(() { _message = 'Password reset email sent. Check your inbox.'; });
		} catch (e) {
			setState(() { _error = e.toString(); });
		} finally {
			if (mounted) setState(() { _loading = false; });
		}
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(title: const Text('Reset password')),
			body: Center(
				child: ConstrainedBox(
					constraints: const BoxConstraints(maxWidth: 420),
					child: Padding(
						padding: const EdgeInsets.all(16),
						child: Form(
							key: _formKey,
							child: Column(
								mainAxisSize: MainAxisSize.min,
								crossAxisAlignment: CrossAxisAlignment.stretch,
								children: [
									TextFormField(
										controller: _emailCtrl,
										keyboardType: TextInputType.emailAddress,
										decoration: const InputDecoration(labelText: 'Email'),
										validator: (v) => (v == null || v.isEmpty || !v.contains('@')) ? 'Enter a valid email' : null,
									),
									const SizedBox(height: 12),
									if (_message != null) Text(_message!, style: const TextStyle(color: Colors.green)),
									if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
									const SizedBox(height: 12),
									FilledButton(
										onPressed: _loading ? null : _submit,
										child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send reset link'),
									),
									const SizedBox(height: 12),
									TextButton(
										onPressed: _loading ? null : () => context.go('/login'),
										child: const Text('Back to sign in'),
									),
								],
							),
						),
					),
				),
			),
		);
	}
}