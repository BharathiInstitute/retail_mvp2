import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_repository_and_provider.dart' show authRepositoryProvider;
import '../theme/theme_extension_helpers.dart';

// App brand used in the header and hero panel
const String _brandName = 'Tulasi Retail ERP';

class LoginScreen extends ConsumerStatefulWidget {
	const LoginScreen({super.key});

	@override
	ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
	final _formKey = GlobalKey<FormState>();
	final _emailCtrl = TextEditingController();
	final _passwordCtrl = TextEditingController();
	final _emailFocus = FocusNode();
	final _passwordFocus = FocusNode();
	bool _loading = false;
	String? _error;
	bool _obscure = true;
	late AnimationController _animCtrl;
	late Animation<double> _fadeAnim;
	late Animation<Offset> _slideAnim;

	@override
	void initState() {
		super.initState();
		_animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
		_fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
		_slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
				.animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
		_animCtrl.forward();
		WidgetsBinding.instance.addPostFrameCallback((_) {
			if (mounted) _emailFocus.requestFocus();
		});
	}

	@override
	void dispose() {
		_animCtrl.dispose();
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
		final isDark = theme.brightness == Brightness.dark;

		return Scaffold(
			body: Container(
				decoration: BoxDecoration(
					gradient: LinearGradient(
						begin: Alignment.topLeft,
						end: Alignment.bottomRight,
						colors: isDark
								? [const Color(0xFF1a1a2e), const Color(0xFF16213e), const Color(0xFF0f3460)]
								: [const Color(0xFFf8fafc), const Color(0xFFe2e8f0), const Color(0xFFcbd5e1)],
					),
				),
				child: LayoutBuilder(
					builder: (context, constraints) {
						final wide = constraints.maxWidth >= 960;

						// Modern glassmorphism login card
						final formCard = FadeTransition(
							opacity: _fadeAnim,
							child: SlideTransition(
								position: _slideAnim,
								child: Center(
									child: ConstrainedBox(
										constraints: const BoxConstraints(maxWidth: 420),
										child: Container(
											margin: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 24),
											decoration: BoxDecoration(
												borderRadius: context.radiusXl,
												color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.85),
												border: Border.all(
													color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6),
													width: 1.5,
												),
												boxShadow: [
													BoxShadow(
														color: cs.primary.withOpacity(0.08),
														blurRadius: 40,
														offset: const Offset(0, 20),
													),
													BoxShadow(
														color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
														blurRadius: 20,
														offset: const Offset(0, 10),
													),
												],
											),
											child: ClipRRect(
												borderRadius: context.radiusXl,
												child: BackdropFilter(
													filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
													child: Padding(
														padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
														child: AutofillGroup(
															child: Form(
																key: _formKey,
																child: Column(
																	mainAxisSize: MainAxisSize.min,
																	crossAxisAlignment: CrossAxisAlignment.stretch,
																	children: [
																		// Logo and brand
																		Row(
																			children: [
																				Container(
																					width: 52,
																					height: 52,
																					decoration: BoxDecoration(
																						gradient: LinearGradient(
																							begin: Alignment.topLeft,
																							end: Alignment.bottomRight,
																							colors: [cs.primary, cs.primary.withOpacity(0.7)],
																						),
																						borderRadius: BorderRadius.circular(14),
																						boxShadow: [
																							BoxShadow(
																								color: cs.primary.withOpacity(0.35),
																								blurRadius: 12,
																								offset: const Offset(0, 4),
																							),
																						],
																					),
																					child: Center(
																						child: Text(
																							'TR',
																							style: tt.titleMedium?.copyWith(
																								color: Colors.white,
																								fontWeight: FontWeight.w800,
																								letterSpacing: 1,
																							),
																						),
																					),
																				),
																				const SizedBox(width: 14),
																				Expanded(
																					child: Column(
																						crossAxisAlignment: CrossAxisAlignment.start,
																						children: [
																							Text(
																								_brandName,
																								style: tt.titleLarge?.copyWith(
																									fontWeight: FontWeight.w800,
																									color: cs.onSurface,
																									letterSpacing: -0.5,
																								),
																							),
																							const SizedBox(height: 2),
																							Text(
																								'Sign in to continue',
																								style: tt.bodySmall?.copyWith(
																									color: cs.onSurfaceVariant,
																									fontWeight: FontWeight.w500,
																								),
																							),
																						],
																					),
																				),
																			],
																		),
																		const SizedBox(height: 32),
																		// Email field
																		_ModernTextField(
																			controller: _emailCtrl,
																			focusNode: _emailFocus,
																			label: 'Email',
																			hint: 'Enter your email',
																			icon: Icons.email_outlined,
																			keyboardType: TextInputType.emailAddress,
																			autofillHints: const [AutofillHints.email],
																			textInputAction: TextInputAction.next,
																			validator: (v) => (v == null || v.isEmpty || !v.contains('@')) ? 'Enter a valid email' : null,
																				onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
																			),
																			context.gapVLg,
																			// Password field
																		_ModernTextField(
																			controller: _passwordCtrl,
																			focusNode: _passwordFocus,
																			label: 'Password',
																			hint: 'Enter your password',
																			icon: Icons.lock_outline_rounded,
																			obscureText: _obscure,
																			autofillHints: const [AutofillHints.password],
																			textInputAction: TextInputAction.done,
																			validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
																			onFieldSubmitted: (_) => _loading ? null : _submit(),
																			suffixIcon: IconButton(
																				icon: Icon(
																					_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
																					color: cs.onSurfaceVariant,
																					size: 20,
																				),
																				onPressed: () => setState(() => _obscure = !_obscure),
																			),
																		),
																		const SizedBox(height: 10),
																		// Error message
																		AnimatedSize(
																			duration: const Duration(milliseconds: 200),
																			child: _error != null
																						? Container(
																								padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
																								margin: const EdgeInsets.only(bottom: 8),
																								decoration: BoxDecoration(
																									color: cs.error.withOpacity(0.1),
																									borderRadius: context.radiusMd,
																									border: Border.all(color: cs.error.withOpacity(0.3)),
																								),
																							child: Row(
																								children: [
																									Icon(Icons.error_outline_rounded, size: 16, color: cs.error),
																									const SizedBox(width: 8),
																									Expanded(
																										child: Text(
																											_error!,
																											style: tt.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.w500),
																										),
																									),
																								],
																							),
																						)
																			: const SizedBox.shrink(),
																	),
																	context.gapVSm,
																	// Sign in button
																		Container(
																			height: 50,
																			decoration: BoxDecoration(
																				gradient: LinearGradient(
																					colors: [cs.primary, cs.primary.withOpacity(0.85)],
																				),
																				borderRadius: BorderRadius.circular(14),
																				boxShadow: [
																					BoxShadow(
																						color: cs.primary.withOpacity(0.35),
																						blurRadius: 12,
																						offset: const Offset(0, 4),
																					),
																				],
																			),
																			child: Material(
																				color: Colors.transparent,
																				child: InkWell(
																					onTap: _loading ? null : _submit,
																					borderRadius: BorderRadius.circular(14),
																					child: Center(
																						child: _loading
																								? SizedBox(
																										width: 22,
																										height: 22,
																										child: CircularProgressIndicator(
																											strokeWidth: 2.5,
																											color: Colors.white,
																										),
																									)
																								: Row(
																										mainAxisAlignment: MainAxisAlignment.center,
																										children: [
																											const Icon(Icons.login_rounded, color: Colors.white, size: 20),
																											const SizedBox(width: 10),
																											Text(
																												'Sign In',
																												style: tt.titleSmall?.copyWith(
																													color: Colors.white,
																													fontWeight: FontWeight.w700,
																													letterSpacing: 0.5,
																												),
																											),
																										],
																									),
																					),
																				),
																			),
																		),
																		const SizedBox(height: 20),
																		// Links row
																		Row(
																			mainAxisAlignment: MainAxisAlignment.spaceBetween,
																			children: [
																				TextButton(
																					onPressed: _loading ? null : () => context.push('/forgot'),
																					style: TextButton.styleFrom(
																						foregroundColor: cs.primary,
																						padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
																					),
																					child: Text(
																						'Forgot password?',
																						style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
																					),
																				),
																				TextButton(
																					onPressed: _loading ? null : () => context.push('/register'),
																					style: TextButton.styleFrom(
																						foregroundColor: cs.primary,
																						padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
																					),
																					child: Text(
																						'Create account',
																						style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
																					),
																				),
																			],
																		),
																		context.gapVSm,
																		Center(
																			child: Text(
																				'v1.0',
																				style: tt.labelSmall?.copyWith(
																					color: cs.onSurfaceVariant.withOpacity(0.6),
																					fontSize: context.sizes.fontXs,
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
								),
							),
						);

						// Modern brand panel with animated elements
						final brandPanel = Container(
							decoration: BoxDecoration(
								gradient: LinearGradient(
									begin: Alignment.topLeft,
									end: Alignment.bottomRight,
									colors: isDark
											? [const Color(0xFF1e3a5f), const Color(0xFF0d1b2a)]
											: [cs.primary.withOpacity(0.08), cs.primary.withOpacity(0.03)],
								),
							),
							child: Stack(
								children: [
									// Background decorative circles
									Positioned(
										top: -80,
										left: -80,
										child: Container(
											width: 300,
											height: 300,
											decoration: BoxDecoration(
												shape: BoxShape.circle,
												color: cs.primary.withOpacity(isDark ? 0.08 : 0.06),
											),
										),
									),
									Positioned(
										bottom: -120,
										right: -60,
										child: Container(
											width: 400,
											height: 400,
											decoration: BoxDecoration(
												shape: BoxShape.circle,
												color: cs.secondary.withOpacity(isDark ? 0.06 : 0.04),
											),
										),
									),
									Positioned(
										top: 100,
										right: 50,
										child: Container(
											width: 100,
											height: 100,
											decoration: BoxDecoration(
												shape: BoxShape.circle,
												color: cs.tertiary.withOpacity(isDark ? 0.1 : 0.05),
											),
										),
									),
									// Main content
									Center(
										child: FadeTransition(
											opacity: _fadeAnim,
											child: SlideTransition(
												position: Tween<Offset>(begin: const Offset(-0.05, 0), end: Offset.zero)
														.animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic)),
												child: Padding(
													padding: const EdgeInsets.all(48),
													child: Column(
														mainAxisSize: MainAxisSize.min,
														crossAxisAlignment: CrossAxisAlignment.center,
														children: [
															// Animated logo
															Container(
																width: 100,
																height: 100,
																decoration: BoxDecoration(
																	gradient: LinearGradient(
																		begin: Alignment.topLeft,
																		end: Alignment.bottomRight,
																		colors: [cs.primary, cs.primary.withOpacity(0.7)],
																	),
																	borderRadius: BorderRadius.circular(28),
																	boxShadow: [
																		BoxShadow(
																			color: cs.primary.withOpacity(0.4),
																			blurRadius: 30,
																			offset: const Offset(0, 10),
																		),
																	],
																),
																child: Center(
																	child: Text(
																		'TR',
																		style: tt.headlineMedium?.copyWith(
																			color: Colors.white,
																			fontWeight: FontWeight.w900,
																			letterSpacing: 2,
																		),
																	),
																),
															),
															const SizedBox(height: 32),
															Text(
																_brandName,
																textAlign: TextAlign.center,
																style: tt.headlineMedium?.copyWith(
																	fontWeight: FontWeight.w900,
																	color: cs.onSurface,
																	letterSpacing: -0.5,
																),
															),
															context.gapVMd,
															Text(
																'Simple. Fast. Reliable retail\nfor your business.',
																textAlign: TextAlign.center,
																style: tt.bodyLarge?.copyWith(
																	color: cs.onSurfaceVariant,
																	height: 1.6,
																),
															),
															const SizedBox(height: 40),
															// Feature badges
															Wrap(
																spacing: 12,
																runSpacing: 12,
																alignment: WrapAlignment.center,
																children: [
																	_FeatureBadge(icon: Icons.inventory_2_outlined, label: 'Inventory', cs: cs),
																	_FeatureBadge(icon: Icons.point_of_sale_outlined, label: 'POS', cs: cs),
																	_FeatureBadge(icon: Icons.analytics_outlined, label: 'Analytics', cs: cs),
																],
															),
														],
													),
												),
											),
										),
									),
								],
							),
						);

						if (wide) {
							return Row(
								children: [
									Expanded(child: brandPanel),
									Expanded(child: formCard),
								],
							);
						} else {
							return SingleChildScrollView(
								child: Column(
									children: [
										const SizedBox(height: 60),
										// Compact mobile header
										FadeTransition(
											opacity: _fadeAnim,
											child: Column(
												children: [
													Container(
														width: 70,
														height: 70,
														decoration: BoxDecoration(
															gradient: LinearGradient(
																colors: [cs.primary, cs.primary.withOpacity(0.7)],
															),
															borderRadius: BorderRadius.circular(20),
															boxShadow: [
																BoxShadow(
																	color: cs.primary.withOpacity(0.35),
																	blurRadius: 20,
																	offset: const Offset(0, 8),
																),
															],
														),
														child: Center(
															child: Text(
																'TR',
																style: tt.titleLarge?.copyWith(
																	color: Colors.white,
																	fontWeight: FontWeight.w900,
																	letterSpacing: 1,
																),
															),
														),
													),
													context.gapVLg,
													Text(
														_brandName,
														style: tt.titleLarge?.copyWith(
															fontWeight: FontWeight.w800,
															color: cs.onSurface,
														),
													),
												],
											),
										),
										formCard,
									],
								),
							);
						}
					},
				),
			),
		);
	}
}

// Modern text field widget
class _ModernTextField extends StatelessWidget {
	final TextEditingController controller;
	final FocusNode focusNode;
	final String label;
	final String hint;
	final IconData icon;
	final bool obscureText;
	final TextInputType? keyboardType;
	final List<String>? autofillHints;
	final TextInputAction? textInputAction;
	final String? Function(String?)? validator;
	final void Function(String)? onFieldSubmitted;
	final Widget? suffixIcon;

	const _ModernTextField({
		required this.controller,
		required this.focusNode,
		required this.label,
		required this.hint,
		required this.icon,
		this.obscureText = false,
		this.keyboardType,
		this.autofillHints,
		this.textInputAction,
		this.validator,
		this.onFieldSubmitted,
		this.suffixIcon,
	});

	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		final isDark = Theme.of(context).brightness == Brightness.dark;
		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				Text(
					label,
					style: TextStyle(
						fontSize: context.sizes.fontSm,
						fontWeight: FontWeight.w600,
						color: cs.onSurface,
						letterSpacing: 0.3,
					),
				),
				context.gapVSm,
				TextFormField(
					controller: controller,
					focusNode: focusNode,
					obscureText: obscureText,
					keyboardType: keyboardType,
					autofillHints: autofillHints,
					textInputAction: textInputAction,
					validator: validator,
					onFieldSubmitted: onFieldSubmitted,
					style: TextStyle(fontSize: context.sizes.fontMd, color: cs.onSurface),
					decoration: InputDecoration(
						hintText: hint,
						hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.6), fontSize: context.sizes.fontMd),
						prefixIcon: Container(
							margin: const EdgeInsets.only(left: 4),
							child: Icon(icon, size: 20, color: cs.primary.withOpacity(0.8)),
						),
						suffixIcon: suffixIcon,
						filled: true,
						fillColor: isDark ? Colors.white.withOpacity(0.06) : cs.surfaceContainerHighest.withOpacity(0.5),
						contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
						border: OutlineInputBorder(
							borderRadius: context.radiusMd,
							borderSide: BorderSide(color: cs.outline.withOpacity(0.2)),
						),
						enabledBorder: OutlineInputBorder(
							borderRadius: context.radiusMd,
							borderSide: BorderSide(color: cs.outline.withOpacity(0.15)),
						),
						focusedBorder: OutlineInputBorder(
							borderRadius: context.radiusMd,
							borderSide: BorderSide(color: cs.primary, width: 1.5),
						),
						errorBorder: OutlineInputBorder(
							borderRadius: context.radiusMd,
							borderSide: BorderSide(color: cs.error.withOpacity(0.5)),
						),
						focusedErrorBorder: OutlineInputBorder(
							borderRadius: context.radiusMd,
							borderSide: BorderSide(color: cs.error, width: 1.5),
						),
					),
				),
			],
		);
	}
}

// Feature badge widget
class _FeatureBadge extends StatelessWidget {
	final IconData icon;
	final String label;
	final ColorScheme cs;
	const _FeatureBadge({required this.icon, required this.label, required this.cs});

	@override
	Widget build(BuildContext context) {
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
			decoration: BoxDecoration(
				color: cs.primary.withOpacity(0.08),
				borderRadius: BorderRadius.circular(30),
				border: Border.all(color: cs.primary.withOpacity(0.15)),
			),
			child: Row(
				mainAxisSize: MainAxisSize.min,
				children: [
					Icon(icon, size: 18, color: cs.primary),
					context.gapHSm,
					Text(
						label,
						style: TextStyle(
							fontSize: context.sizes.fontSm,
							fontWeight: FontWeight.w600,
							color: cs.primary,
						),
					),
				],
			),
		);
	}
}
