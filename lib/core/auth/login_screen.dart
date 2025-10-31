import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth.dart' show authRepositoryProvider;

class LoginScreen extends ConsumerStatefulWidget {
	const LoginScreen({super.key});

	@override
	ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
	final _formKey = GlobalKey<FormState>();
	final _emailCtrl = TextEditingController();
	final _passwordCtrl = TextEditingController();
	final _emailFocus = FocusNode();
	final _passwordFocus = FocusNode();
	bool _loading = false;
	String? _error;

	@override
	void initState() {
		super.initState();
		// On web/desktop, after navigating from an authenticated shell, a pending rebuild
		// can steal focus; request focus on the next frame to ensure the email field is ready.
		WidgetsBinding.instance.addPostFrameCallback((_) {
			if (mounted) {
				_emailFocus.requestFocus();
			}
		});
	}

	@override
	void didChangeDependencies() {
		super.didChangeDependencies();
		// Redundant focus request in case previous overlays or route pops stole it.
		WidgetsBinding.instance.addPostFrameCallback((_) {
			if (!mounted) return;
			if (!_emailFocus.hasFocus && !_passwordFocus.hasFocus) {
				_emailFocus.requestFocus();
			}
		});
	}

	@override
	void dispose() {
		_emailCtrl.dispose();
		_passwordCtrl.dispose();
		_emailFocus.dispose();
		_passwordFocus.dispose();
		super.dispose();
	}

	Future<void> _submit() async {
		if (!_formKey.currentState!.validate()) return;
		setState(() { _loading = true; _error = null; });
		final repo = ref.read(authRepositoryProvider);
		try {
			await repo.signInWithEmailPassword(
				email: _emailCtrl.text.trim(),
				password: _passwordCtrl.text,
			);
			// Do not navigate here; GoRouter's redirect will handle moving away from /login
			// once auth state changes and permissions are available.
		} catch (e) {
			setState(() { _error = e.toString(); });
		} finally {
			if (mounted) setState(() { _loading = false; });
		}
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(title: const Text('Sign in')),
			body: Center(
				child: ConstrainedBox(
					constraints: const BoxConstraints(maxWidth: 420),
									child: Padding(
						padding: const EdgeInsets.all(16),
						child: AutofillGroup(
							child: Form(
								key: _formKey,
								child: Column(
									mainAxisSize: MainAxisSize.min,
									crossAxisAlignment: CrossAxisAlignment.stretch,
									children: [
																			TextFormField(
																					focusNode: _emailFocus,
											controller: _emailCtrl,
											autofillHints: const [AutofillHints.username, AutofillHints.email],
											keyboardType: TextInputType.emailAddress,
																					textInputAction: TextInputAction.next,
																					autofocus: true,
											decoration: const InputDecoration(labelText: 'Email'),
											validator: (v) => (v == null || v.isEmpty || !v.contains('@')) ? 'Enter a valid email' : null,
																					onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
										),
										const SizedBox(height: 12),
																				TextFormField(
																					focusNode: _passwordFocus,
											controller: _passwordCtrl,
											autofillHints: const [AutofillHints.password],
											obscureText: true,
																					textInputAction: TextInputAction.done,
											decoration: const InputDecoration(labelText: 'Password'),
											validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
																					onFieldSubmitted: (_) => _loading ? null : _submit(),
										),
										const SizedBox(height: 12),
										if (_error != null)
											Text(
												_error!,
												style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
											),
										const SizedBox(height: 12),
										FilledButton(
											onPressed: _loading ? null : _submit,
											child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
										),
										const SizedBox(height: 12),
										TextButton(
											onPressed: _loading ? null : () => context.push('/forgot'),
											child: const Text('Forgot password?'),
										),
										TextButton(
											onPressed: _loading ? null : () => context.push('/register'),
											child: const Text('Create an account'),
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