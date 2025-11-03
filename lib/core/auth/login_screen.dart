import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth.dart' show authRepositoryProvider;

// App brand used in the header and hero panel
const String _brandName = 'Tulasi Retail ERP';

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
	bool _obscure = true;

	@override
	void initState() {
		super.initState();
		// Ensure the email field receives focus after the first frame (web/desktop)
		WidgetsBinding.instance.addPostFrameCallback((_) {
			if (mounted) _emailFocus.requestFocus();
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
		setState(() {
			_loading = true;
			_error = null;
		});
		final repo = ref.read(authRepositoryProvider);
		try {
			await repo.signInWithEmailPassword(
				email: _emailCtrl.text.trim(),
				password: _passwordCtrl.text,
			);
			// GoRouter redirect handles navigation after auth state changes.
		} catch (e) {
			setState(() => _error = e.toString());
		} finally {
			if (mounted) setState(() => _loading = false);
		}
	}

	@override
	Widget build(BuildContext context) {
		final theme = Theme.of(context);
		final cs = theme.colorScheme;
		final tt = theme.textTheme;

		return Scaffold(
			backgroundColor: cs.surface,
			body: LayoutBuilder(
				builder: (context, constraints) {
					final wide = constraints.maxWidth >= 960;

					final formCard = Center(
						child: ConstrainedBox(
							constraints: const BoxConstraints(maxWidth: 460),
							child: Card(
								elevation: 10,
								margin: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: 24),
								shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
								child: Padding(
									padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
									child: Theme(
										data: theme.copyWith(
											inputDecorationTheme: InputDecorationTheme(
												filled: true,
												fillColor: cs.surfaceContainerHighest.withOpacity(0.18),
												border: OutlineInputBorder(
													borderRadius: BorderRadius.circular(12),
												),
											),
										),
										child: AutofillGroup(
											child: Form(
												key: _formKey,
												child: Column(
													mainAxisSize: MainAxisSize.min,
													crossAxisAlignment: CrossAxisAlignment.stretch,
													children: [
														Row(
															children: [
																CircleAvatar(
																	radius: 22,
																	backgroundColor: cs.primary,
																	child: Text(
																		'TR',
																		style: tt.titleSmall?.copyWith(
																			color: cs.onPrimary,
																			fontWeight: FontWeight.w800,
																		),
																	),
																),
																const SizedBox(width: 12),
																Expanded(
																	child: Column(
																		crossAxisAlignment: CrossAxisAlignment.start,
																		children: [
																			Text(_brandName, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
																			Text('Welcome back. Please sign in.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
																		],
																	),
																),
															],
														),
														const SizedBox(height: 16),
														TextFormField(
															focusNode: _emailFocus,
															controller: _emailCtrl,
															autofocus: true,
															autofillHints: const [AutofillHints.username, AutofillHints.email],
															keyboardType: TextInputType.emailAddress,
															textInputAction: TextInputAction.next,
															decoration: const InputDecoration(
																labelText: 'Email address',
																prefixIcon: Icon(Icons.mail_outline),
															),
															validator: (v) => (v == null || v.isEmpty || !v.contains('@')) ? 'Enter a valid email' : null,
															onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
														),
														const SizedBox(height: 12),
														TextFormField(
															focusNode: _passwordFocus,
															controller: _passwordCtrl,
															autofillHints: const [AutofillHints.password],
															obscureText: _obscure,
															textInputAction: TextInputAction.done,
															decoration: InputDecoration(
																labelText: 'Password',
																prefixIcon: const Icon(Icons.lock_outline),
																suffixIcon: IconButton(
																	tooltip: _obscure ? 'Show password' : 'Hide password',
																	icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
																	onPressed: () => setState(() => _obscure = !_obscure),
																),
															),
															validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
															onFieldSubmitted: (_) => _loading ? null : _submit(),
														),
														const SizedBox(height: 8),
														if (_error != null) ...[
															Text(_error!, style: tt.labelSmall?.copyWith(color: cs.error)),
															const SizedBox(height: 8),
														],
														FilledButton.icon(
															onPressed: _loading ? null : _submit,
															icon: _loading
																	? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
																	: const Icon(Icons.login),
															label: const Text('Sign in'),
															style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
														),
														Row(
															mainAxisAlignment: MainAxisAlignment.spaceBetween,
															children: [
																TextButton(
																	onPressed: _loading ? null : () => context.push('/forgot'),
																	child: const Text('Forgot password?'),
																),
																TextButton(
																	onPressed: _loading ? null : () => context.push('/register'),
																	child: const Text('Create account'),
																),
															],
														),
														const SizedBox(height: 4),
														Align(
															alignment: Alignment.centerRight,
															child: Text('v1.0', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
														),
													],
												),
											),
										),
									),
								),
							),
						),
					);

					final brandPanel = Container(
						decoration: BoxDecoration(
							gradient: LinearGradient(
								begin: Alignment.topLeft,
								end: Alignment.bottomRight,
								colors: [
								  cs.primary.withOpacity(0.14),
								  cs.secondary.withOpacity(0.10),
								],
							),
						),
						child: Center(
							child: Padding(
								padding: const EdgeInsets.all(32),
								child: Column(
									mainAxisSize: MainAxisSize.min,
									crossAxisAlignment: CrossAxisAlignment.center,
									children: [
										CircleAvatar(
											radius: 40,
											backgroundColor: cs.primary,
											child: Text('TR', style: tt.headlineSmall?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w900)),
										),
										const SizedBox(height: 20),
										Text(_brandName, textAlign: TextAlign.center, style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
										const SizedBox(height: 8),
										Text('Simple. Fast. Reliable retail for your business.', textAlign: TextAlign.center, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
									],
								),
							),
						),
					);

					if (wide) {
						return Row(
							children: [
								// Brand hero panel
								Expanded(child: brandPanel),
								// Login form
								Expanded(child: formCard),
							],
						);
					} else {
						return SingleChildScrollView(
							child: Column(
								children: [
									const SizedBox(height: 48),
									// Compact brand header for small screens
									Padding(
										padding: const EdgeInsets.symmetric(horizontal: 24),
										child: Row(
											mainAxisAlignment: MainAxisAlignment.center,
											children: [
												CircleAvatar(
													radius: 20,
													backgroundColor: cs.primary,
													child: Text('TR', style: tt.titleSmall?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800)),
												),
												const SizedBox(width: 12),
												Flexible(
													child: Text(_brandName, overflow: TextOverflow.ellipsis, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
												),
											],
										),
									),
									const SizedBox(height: 16),
									formCard,
								],
							),
						);
					}
				},
			),
		);
	}
}
