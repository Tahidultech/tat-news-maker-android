import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as windows;

class AppBrowserController {
  windows.WebviewController? _windowsController;
  mobile.WebViewController? _mobileController;
  final StreamController<String> _mobileUrlChanges =
      StreamController<String>.broadcast();
  String? _lastMobileUrl;

  bool get isWindows => Platform.isWindows;

  Stream<String> get url =>
      isWindows ? _windowsController!.url : _mobileUrlChanges.stream;

  Future<void> initialize() async {
    if (Platform.isWindows) {
      final controller = windows.WebviewController();
      await controller.initialize();
      _windowsController = controller;
      return;
    }

    if (Platform.isAndroid) {
      final controller = mobile.WebViewController();
      await controller.setJavaScriptMode(mobile.JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        mobile.NavigationDelegate(
          onPageStarted: _publishMobileUrl,
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _publishMobileUrl(url);
          },
        ),
      );
      _mobileController = controller;
      return;
    }

    throw UnsupportedError('The in-app browser supports Windows and Android.');
  }

  Future<void> setPopupWindowPolicy(
    windows.WebviewPopupWindowPolicy policy,
  ) async {
    if (Platform.isWindows) {
      await _windowsController!.setPopupWindowPolicy(policy);
    }
  }

  Future<void> loadUrl(String url) async {
    if (Platform.isWindows) {
      await _windowsController!.loadUrl(url);
      return;
    }

    if (Platform.isAndroid) {
      _lastMobileUrl = null;
      await _mobileController!.loadRequest(Uri.parse(url));
      return;
    }

    throw UnsupportedError('The in-app browser supports Windows and Android.');
  }

  Widget buildView() {
    if (Platform.isWindows) {
      return windows.Webview(_windowsController!);
    }

    if (Platform.isAndroid) {
      return mobile.WebViewWidget(controller: _mobileController!);
    }

    throw UnsupportedError('The in-app browser supports Windows and Android.');
  }

  Future<void> dispose() async {
    await _windowsController?.dispose();
    await _mobileUrlChanges.close();
  }

  void _publishMobileUrl(String url) {
    if (url == _lastMobileUrl) return;
    _lastMobileUrl = url;
    _mobileUrlChanges.add(url);
  }
}
