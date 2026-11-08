import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Blocks access to [child] until the Cloudflare Worker confirms a valid key.
class AccessGate extends StatefulWidget {
  const AccessGate({super.key, required this.child});

  final Widget child;

  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  static const String _apiBaseUrl = String.fromEnvironment(
    'CLOUDFLARE_ACCESS_URL',
    defaultValue: 'https://news-maker-access.tahidul-it.workers.dev',
  );

  final TextEditingController _licenseController = TextEditingController();
  bool _isLoading = true;
  bool _isAllowed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _restoreAndCheck();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<File> _licenseFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}news_maker_license');
  }

  Future<void> _restoreAndCheck() async {
    if (_apiBaseUrl.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _message = 'Access verification URL is not configured.';
      });
      return;
    }

    try {
      final file = await _licenseFile();
      if (!await file.exists()) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final key = (await file.readAsString()).trim();
      if (key.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      if (!mounted) return;
      _licenseController.text = key;
      await _verify(key, saveKey: false);
    } on FileSystemException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _message = 'Could not read the saved license. Please enter it again.';
      });
    }
  }

  Future<void> _verify(String key, {required bool saveKey}) async {
    final normalizedKey = key.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(normalizedKey)) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _message = 'Enter a valid 32-character license key.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final baseUrl = _apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/check'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'appname': 'news_maker_bd',
              'content': 'cominity',
              'license_key': normalizedKey,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _message = _responseMessage(response);
        });
        return;
      }

      final result = jsonDecode(response.body);
      if (result is! Map<String, dynamic> || result['active'] != true) {
        throw const FormatException('Unexpected access-check response');
      }

      if (saveKey) {
        final file = await _licenseFile();
        await file.writeAsString(normalizedKey, flush: true);
      }
      if (!mounted) return;
      setState(() {
        _isAllowed = true;
        _isLoading = false;
        _message = null;
      });
    } on TimeoutException {
      _setFailure(
        'Could not connect to Cloudflare. Check your internet connection and try again.',
      );
    } on http.ClientException {
      _setFailure(
        'Could not connect to Cloudflare. Check your internet connection and try again.',
      );
    } on FileSystemException {
      _setFailure('Could not save the license key. Please try again.');
    } on FormatException {
      _setFailure('Received an invalid access-check response from Cloudflare.');
    }
  }

  String _responseMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['message'] is String) {
        return body['message'] as String;
      }
    } on FormatException {
      return 'Access check failed (${response.statusCode}).';
    }
    return 'Access check failed (${response.statusCode}).';
  }

  void _setFailure(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isAllowed) return widget.child;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _isLoading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Verify License',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      if (_message != null) ...[
                        Text(_message!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _licenseController,
                        decoration: const InputDecoration(
                          labelText: 'License key',
                          border: OutlineInputBorder(),
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _verify(
                          _licenseController.text,
                          saveKey: true,
                        ),
                        child: const Text('Verify and Continue'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
