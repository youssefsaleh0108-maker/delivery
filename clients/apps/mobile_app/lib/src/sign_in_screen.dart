import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Signing in without leaving the app.
///
/// <p>This replaces the Chrome custom tab. Android will not let an app hide the address bar in one
/// — that is a deliberate anti-phishing measure — so every sign-in used to open a browser showing a
/// bare IP address, which is exactly what a phishing page looks like.
///
/// <p><strong>What that costs.</strong> The password is typed into this app rather than into a page
/// served by Keycloak, so the app is trusted with it. That rules out SSO and a second factor, and
/// the OAuth spec discourages it for third-party clients. It is defensible here because this is the
/// platform's own first-party app against the platform's own realm — see
/// [AuthService.signInWithPassword].
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.authService,
    required this.onSignedIn,
    required this.onBack,
    required this.onCreateAccount,
  });

  final AuthService authService;
  final ValueChanged<AuthSession> onSignedIn;
  final VoidCallback onBack;
  final VoidCallback onCreateAccount;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  bool _busy = false;
  bool _reveal = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final AuthSession session = await widget.authService
          .signInWithPassword(_username.text, _password.text);
      if (!mounted) return;
      widget.onSignedIn(session);
    } on AuthException catch (e) {
      // Keycloak's own wording, already softened in AuthService. Shown on the form rather than in
      // a snackbar: it is about what was typed, so it belongs next to it.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Anything that is not an AuthException is the network, not the credentials — saying
        // "wrong password" here would send somebody to reset a password that is perfectly fine.
        _error = DeliveryStrings.of(context).couldNotReachTheServer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _busy ? null : widget.onBack),
        title: Text(t.signIn),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DeliverySpacing.xl),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(t.welcomeBack, style: theme.textTheme.headlineMedium),
                const SizedBox(height: DeliverySpacing.xs),
                Text(t.signInPrompt, style: theme.textTheme.bodyMedium),
                const SizedBox(height: DeliverySpacing.xl),

                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  autofillHints: const <String>[AutofillHints.username],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  // No autocorrect and no capitals: both mangle a username, and the resulting
                  // failure looks like a wrong password rather than a keyboard being helpful.
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: t.usernameOrEmail,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (String? v) =>
                      (v == null || v.trim().isEmpty) ? t.requiredField : null,
                ),
                const SizedBox(height: DeliverySpacing.md),

                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  autofillHints: const <String>[AutofillHints.password],
                  // Masked by default, with a reveal. A password field that cannot be revealed is
                  // the reason people mistype one three times on a phone keyboard.
                  obscureText: !_reveal,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _busy ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: t.password,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
                      tooltip: _reveal ? t.hide : t.show,
                      onPressed: () => setState(() => _reveal = !_reveal),
                    ),
                  ),
                  validator: (String? v) =>
                      (v == null || v.isEmpty) ? t.requiredField : null,
                ),

                if (_error != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.md),
                  Container(
                    padding: const EdgeInsets.all(DeliverySpacing.md),
                    decoration: BoxDecoration(
                      color: DeliveryColors.brandSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DeliveryColors.brandLine),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.error_outline, color: DeliveryColors.brand, size: 20),
                        const SizedBox(width: DeliverySpacing.sm),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(color: DeliveryColors.brandDark)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: DeliverySpacing.xl),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: DeliveryColors.white),
                        )
                      : Text(t.signIn),
                ),

                const SizedBox(height: DeliverySpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(t.noAccountYet, style: theme.textTheme.bodyMedium),
                    TextButton(
                      onPressed: _busy ? null : widget.onCreateAccount,
                      child: Text(t.createAccount),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
