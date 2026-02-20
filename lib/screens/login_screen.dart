import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import '../services/repository.dart';
import '../services/biometric_service.dart';
import 'main_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  final _repository = Repository();
  final _biometricService = BiometricService();

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final available = await _biometricService.isBiometricAvailable();
    final enabled = await _biometricService.isBiometricLoginEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });

      // Auto-trigger biometric login if enabled
      if (available && enabled) {
        _loginWithBiometrics();
      }
    }
  }

  Future<void> _loginWithBiometrics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authenticated = await _biometricService.authenticate();
      if (!authenticated) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final credentials = await _biometricService.getCredentials();
      if (credentials == null || credentials.email.isEmpty || credentials.password.isEmpty) {
        // Credentials missing — disable biometrics so user isn't stuck
        await _biometricService.setBiometricLoginEnabled(false);
        if (mounted) {
          setState(() {
            _biometricEnabled = false;
            _errorMessage = 'Stored credentials not found. Please log in with email and password, then re-enable biometrics.';
            _isLoading = false;
          });
        }
        return;
      }

      final success = await _repository.login(credentials.email, credentials.password);
      if (success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainShell()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Biometric login failed. Please use email and password.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Read directly from controllers for reliability
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      try {
        final success = await _repository.login(email, password);

        if (success && mounted) {
          if (_biometricAvailable) {
            if (_biometricEnabled) {
              // Already enabled — silently refresh stored credentials
              await _biometricService.saveCredentials(email, password);
            } else {
              // Not yet enabled — offer to enable
              await _offerBiometricSetup(email, password);
            }
          }

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const MainShell()),
            );
          }
        }
      } catch (e) {
        String errorMsg;

        if (e.toString().contains('Authentication endpoint not found')) {
          errorMsg = 'Server connection error. Please try again later.';
        } else if (e.toString().contains('Invalid email or password')) {
          errorMsg = 'Invalid email or password. Please try again.';
        } else if (e.toString().contains('Internet connection required')) {
          errorMsg = 'No internet connection. Please check your connection and try again.';
        } else if (e.toString().contains('Server error')) {
          errorMsg = 'Server is currently unavailable. Please try again later.';
        } else {
          errorMsg = 'Login failed: ${e.toString()}';
        }

        if (mounted) {
          setState(() {
            _errorMessage = errorMsg;
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _offerBiometricSetup(String email, String password) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable Biometric Login'),
        content: const Text(
          'Would you like to use Face ID or fingerprint to sign in next time?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('NOT NOW'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('ENABLE'),
          ),
        ],
      ),
    );

    if (result == true) {
      final saved = await _biometricService.saveCredentials(email, password);
      if (saved) {
        await _biometricService.setBiometricLoginEnabled(true);
        if (mounted) {
          setState(() => _biometricEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Biometric login enabled!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save credentials. Biometric login not enabled.')),
          );
        }
      }
    }
  }

  void _loginAsGuest() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vineyard Inventory'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo or Image
              Icon(
                Icons.eco,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Vineyard Inventory',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Login Form
              FormBuilder(
                key: _formKey,
                child: Column(
                  children: [
                    FormBuilderTextField(
                      name: 'email',
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(),
                        FormBuilderValidators.email(),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'password',
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outlined),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(),
                        FormBuilderValidators.minLength(6),
                      ]),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('LOGIN'),
                      ),
                    ),

                    // Biometric login button
                    if (_biometricAvailable && _biometricEnabled) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _loginWithBiometrics,
                          icon: const Icon(Icons.fingerprint, size: 28),
                          label: const Text('Sign in with Biometrics'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).primaryColor,
                            side: BorderSide(color: Theme.of(context).primaryColor),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _loginAsGuest,
                          child: const Text('Continue as Guest'),
                        ),
                        const SizedBox(width: 16),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const RegisterScreen()),
                            );
                          },
                          child: const Text('Create Account'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
