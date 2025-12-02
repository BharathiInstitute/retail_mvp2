import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/theme_extension_helpers.dart';
import 'auth_repository_and_provider.dart' show authRepositoryProvider;

class RegisterScreen extends ConsumerStatefulWidget {
	const RegisterScreen({super.key});

	@override
	ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
	final _formKey = GlobalKey<FormState>();
	final _emailCtrl = TextEditingController();
	final _passwordCtrl = TextEditingController();
	bool _loading = false;
	String? _error;

	@override
	void dispose() {
		_emailCtrl.dispose();
		_passwordCtrl.dispose();
		super.dispose();
	}

	Future<void> _submit() async {
		if (!_formKey.currentState!.validate()) return;
		setState(() { _loading = true; _error = null; });
		final repo = ref.read(authRepositoryProvider);
		try {
			await repo.createUserWithEmailPassword(
				email: _emailCtrl.text.trim(),
				password: _passwordCtrl.text,
			);
			// Do not navigate here; GoRouter redirect will route based on auth state and permissions.
		} catch (e) {
			setState(() { _error = e.toString(); });
		} finally {
			if (mounted) setState(() { _loading = false; });
		}
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(title: const Text('Create account')),
			body: Center(
				child: ConstrainedBox(
					constraints: const BoxConstraints(maxWidth: 420),
					child: Padding(
						padding: context.padLg,
						child: AutofillGroup(
							child: Form(
								key: _formKey,
								child: Column(
									mainAxisSize: MainAxisSize.min,
									crossAxisAlignment: CrossAxisAlignment.stretch,
									children: [
										TextFormField(
											controller: _emailCtrl,
											autofillHints: const [AutofillHints.username, AutofillHints.email],
											keyboardType: TextInputType.emailAddress,
											decoration: const InputDecoration(labelText: 'Email'),
											validator: (v) => (v == null || v.isEmpty || !v.contains('@')) ? 'Enter a valid email' : null,
										),
										context.gapVMd,
										TextFormField(
											controller: _passwordCtrl,
											autofillHints: const [AutofillHints.newPassword],
											obscureText: true,
											decoration: const InputDecoration(labelText: 'Password'),
											validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
										),
										context.gapVMd,
										if (_error != null)
											Text(
												_error!,
												style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
											),
										context.gapVMd,
										FilledButton(
											onPressed: _loading ? null : _submit,
											child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create account'),
										),
										context.gapVMd,
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
			),
		);
	}
}