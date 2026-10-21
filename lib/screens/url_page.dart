import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/app_config.dart';
import '../utils/session_manager.dart';
import '../services/api_service.dart';
import 'login_page.dart';

class UrlPage extends StatefulWidget {
  const UrlPage({super.key});

  @override
  State<UrlPage> createState() => _UrlPageState();
}

class _UrlPageState extends State<UrlPage> {
  final TextEditingController urlController = TextEditingController();

  bool isLoading = false;
  bool isValidUrl = false;
  String validationMessage = '';

  @override
  void initState() {
    super.initState();
    _loadExistingUrl();
  }

  Future<void> _loadExistingUrl() async {
    try {
      final isSessionActive = await SessionManager.isSessionActive();

      if (!isSessionActive) return;

      final existingUrl = await SessionManager.getSchoolUrl();

      if (!mounted) return;

      if (existingUrl.isNotEmpty) {
        urlController.text = existingUrl;
        _validateUrlInput(existingUrl);
      }
    } catch (e) {
      debugPrint('Error loading existing school URL: $e');
    }
  }

  void _validateUrlInput(String input) {
    final enteredUrl = input.trim();

    if (enteredUrl.isEmpty) {
      setState(() {
        isValidUrl = false;
        validationMessage = '';
      });
      return;
    }

    if (!enteredUrl.startsWith('http://') &&
        !enteredUrl.startsWith('https://')) {
      setState(() {
        isValidUrl = false;
        validationMessage = 'URL must start with http:// or https://';
      });
      return;
    }

    final isValid = _isValidUrl(enteredUrl);

    setState(() {
      isValidUrl = isValid;
      validationMessage = isValid
          ? '✓ Valid URL format'
          : 'Please enter a valid URL format '
                '(e.g., https://your-school.com)';
    });
  }

  // Open the QR scanner and insert its result into the URL field.
  Future<void> _scanQrCode() async {
    if (isLoading) return;

    final scannedValue = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

    if (!mounted || scannedValue == null) return;

    final scannedUrl = scannedValue.trim();

    if (scannedUrl.isEmpty) return;

    urlController.value = TextEditingValue(
      text: scannedUrl,
      selection: TextSelection.collapsed(offset: scannedUrl.length),
    );

    _validateUrlInput(scannedUrl);
    FocusScope.of(context).unfocus();

    if (!_isValidUrl(scannedUrl)) {
      showError(
        'The QR code does not contain a valid school URL. '
        'Please scan another code or enter the URL manually.',
      );
    }
  }

  Future<void> handleSubmit() async {
    final enteredUrl = urlController.text.trim();

    if (enteredUrl.isEmpty) {
      showError('Please enter your school URL');
      return;
    }

    if (!enteredUrl.startsWith('http://') &&
        !enteredUrl.startsWith('https://')) {
      showError(
        'URL must start with http:// or https://. '
        'Example: https://your-school.com',
      );
      return;
    }

    if (!_isValidUrl(enteredUrl)) {
      showError(
        'Please enter a valid URL format. '
        'Example: https://your-school.com',
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Test URL connectivity.
      final isConnected = await _testUrlConnectivity(enteredUrl);

      if (!mounted) return;

      if (!isConnected) {
        showError(
          'Warning: Could not verify URL connectivity. '
          'Please check the URL and your internet connection.',
        );
      }

      // Verify school registration before saving the URL.
      final verificationResult = await ApiService.verifySchoolRegistration(
        enteredUrl,
      );

      if (!mounted) return;

      final isVerified = verificationResult['isVerified'] == true;
      final isNetworkError = verificationResult['isNetworkError'] == true;

      if (!isVerified) {
        final verificationMessage =
            verificationResult['message'] ??
            (isNetworkError
                ? 'Unable to verify school at the moment. '
                      'Please try again later.'
                : 'Your school is not registered. '
                      'Please register your school to continue.');

        showError(verificationMessage.toString());
        return;
      }

      // Remove trailing slashes before saving.
      final urlToSave = enteredUrl.replaceFirst(RegExp(r'/+$'), '');

      // Save the school URL.
      final urlSaved = await AppConfig.setBaseUrl(urlToSave);

      if (!mounted) return;

      if (!urlSaved) {
        showError('Failed to save URL. Please try again.');
        return;
      }

      // Initialize the session.
      final sessionInitialized = await SessionManager.initializeSession(
        urlToSave,
      );

      if (!sessionInitialized) {
        debugPrint('Warning: Session initialization failed.');
      }

      // Load application configuration.
      try {
        final appConfig = await ApiService.getAppConfiguration();

        await AppConfig.saveAppConfiguration(appConfig);

        if (!mounted) return;

        showSuccess('URL configured successfully! App settings loaded.');
      } catch (configError) {
        debugPrint('Error loading app configuration: $configError');

        if (!mounted) return;

        showSuccess(
          'URL configured successfully! '
          'You can now proceed to login.',
        );
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPageUI()),
      );
    } catch (e) {
      debugPrint('Error configuring school URL: $e');

      if (mounted) {
        showError('Connection error. Please check the URL and try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);

      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return false;
      }

      if (uri.host.isEmpty || !uri.host.contains('.')) {
        return false;
      }

      if (uri.host.startsWith('.') || uri.host.endsWith('.')) {
        return false;
      }

      // Validate domain labels.
      final domainPattern = RegExp(
        r'^(?=.{1,253}$)'
        r'(?:[a-zA-Z0-9]'
        r'(?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+'
        r'[a-zA-Z0-9]'
        r'(?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
      );

      if (!domainPattern.hasMatch(uri.host)) {
        return false;
      }

      if (uri.port < 1 || uri.port > 65535) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _testUrlConnectivity(String url) async {
    final baseUrl = url.replaceFirst(RegExp(r'/+$'), '');

    final testEndpoints = [
      '$baseUrl/api/test',
      '$baseUrl/api/webservice/test',
      '$baseUrl/app',
      '$baseUrl/api/webservice/getlessonplan',
      baseUrl,
    ];

    for (final endpoint in testEndpoints) {
      try {
        final uri = Uri.parse(endpoint);

        final response = await http
            .get(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Auth-Key': AppConfig.authKey,
                'Client-Service': AppConfig.clientService,
              },
            )
            .timeout(const Duration(seconds: 10));

        // Any HTTP response confirms that a server responded.
        if (response.statusCode >= 200 && response.statusCode < 600) {
          return true;
        }
      } catch (e) {
        debugPrint('Endpoint check failed for $endpoint: $e');
      }
    }

    // Fallback: test the base URL without custom headers.
    try {
      final response = await http
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 5));

      return response.statusCode >= 200 && response.statusCode < 600;
    } catch (e) {
      debugPrint('Base URL connectivity test failed: $e');
      return false;
    }
  }

  void showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Fixed bottom-left branding.
  Widget _buildPoweredBy() {
    return Positioned(
      left: 16,
      bottom: 8,
      child: SafeArea(
        child: IgnorePointer(
          child: Text(
            'Powered by SMART SCHOOL',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.75),
                  blurRadius: 5,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/img_login_background.png'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenHeight = constraints.maxHeight;
              final screenWidth = constraints.maxWidth;
              final horizontalPadding = screenWidth * 0.06;

              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: screenHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: screenHeight * 0.1),

                          // School logo.
                          _buildBookIcon(),

                          SizedBox(height: screenHeight * 0.04),

                          // URL input and connection button.
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildUrlField(),
                                const SizedBox(height: 16),
                                _buildConnectButton(),
                                const SizedBox(height: 12),
                                const Text(
                                  'Enter your school URL manually '
                                  'or scan its QR code. We will verify '
                                  'the URL and store it for future logins.',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.1),
                        ],
                      ),
                    ),
                  ),

                  // Always displayed at the bottom-left.
                  _buildPoweredBy(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBookIcon() {
    return SizedBox(
      width: 80,
      height: 80,
      child: Image.asset(
        'assets/images/school_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.menu_book,
              size: 40,
              color: Color(0xFF4CAF50),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUrlField() {
    return TextField(
      controller: urlController,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.language, color: Colors.black87),
        suffixIcon: IconButton(
          tooltip: 'Scan QR code',
          icon: const Icon(
            Icons.qr_code_scanner,
            color: Color(0xFF4CAF50),
            size: 28,
          ),
          onPressed: isLoading ? null : _scanQrCode,
        ),
        hintText: 'Enter URL or scan QR code',
        hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        errorText: validationMessage.isNotEmpty && !isValidUrl
            ? validationMessage
            : null,
        helperText: isValidUrl ? validationMessage : null,
        helperStyle: const TextStyle(color: Colors.green),
      ),
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      onChanged: _validateUrlInput,
      onSubmitted: (_) {
        if (!isLoading && isValidUrl) {
          handleSubmit();
        }
      },
      style: const TextStyle(fontSize: 15, color: Colors.black87),
    );
  }

  Widget _buildConnectButton() {
    final isEnabled = !isLoading && isValidUrl;

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isEnabled ? const Color(0xFF4CAF50) : Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isEnabled ? handleSubmit : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  Icons.arrow_forward,
                  size: 20,
                  color: isEnabled ? Colors.white : Colors.grey[600],
                ),
              const SizedBox(width: 8),
              Text(
                isLoading ? 'Connecting...' : 'Connect to School',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isEnabled ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// QR scanner page.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _hasScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();

      if (value != null && value.isNotEmpty) {
        _hasScanned = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan School QR Code'),
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: MobileScannerController(
              formats: const [BarcodeFormat.qrCode],
              detectionSpeed: DetectionSpeed.noDuplicates,
            ),
            onDetect: _onDetect,
          ),
          // QR scanning frame.
          IgnorePointer(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF4CAF50), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // Scanning instructions.
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Point your camera at the school QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
