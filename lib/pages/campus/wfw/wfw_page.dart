import 'dart:async';

import 'package:bugaoshan/injection/injector.dart';
import 'package:bugaoshan/l10n/app_localizations.dart';
import 'package:bugaoshan/services/auth/wfw_auth.dart';
import 'package:bugaoshan/widgets/route/router_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:os_type/os_type.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bugaoshan/widgets/webview/webview_unsupported_page.dart';

/// 微服务页面 —— 内嵌 wfw.scu.edu.cn WebView，注入 WfwAuth 的 session cookie。
class WfwPage extends StatefulWidget {
  const WfwPage({super.key});

  @override
  State<WfwPage> createState() => _WfwPageState();
}

class _WfwPageState extends State<WfwPage> {
  InAppWebViewController? _controller;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _errorHtmlTemplate = '';

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/webview_error.html').then((s) {
      _errorHtmlTemplate = s;
    });
    _injectCookies();
  }

  Future<void> _injectCookies() async {
    try {
      final wfwAuth = getIt<WfwAuth>();
      await wfwAuth.ensureAuthenticated();
      if (!wfwAuth.isReady) return;

      final client = await wfwAuth.getClient();
      final cookies = client.cookiesForUrl('https://wfw.scu.edu.cn/');
      if (cookies.isEmpty) {
        debugPrint('WfwPage: no cookies to inject');
        return;
      }

      final cm = CookieManager.instance();
      for (final entry in cookies.entries) {
        await cm.setCookie(
          url: WebUri('https://wfw.scu.edu.cn'),
          name: entry.key,
          value: entry.value,
        );
      }
      debugPrint('WfwPage: injected ${cookies.length} cookies: ${cookies.keys.join(', ')}');
    } catch (e) {
      debugPrint('WfwPage: cookie injection failed: $e');
    }
  }

  // ---- WebView callbacks ----

  void _onWebViewCreated(InAppWebViewController ctrl) {
    _controller = ctrl;
  }

  Future<void> _onLoadStart(InAppWebViewController ctrl, Uri? url) async {
    if (!mounted) return;
    setState(() => _loading = true);
  }

  Future<void> _onLoadStop(InAppWebViewController ctrl, Uri? url) async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 50));
    final c = _controller;
    if (c == null) return;
    final back = await c.canGoBack();
    final forward = await c.canGoForward();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _canGoBack = back;
      _canGoForward = forward;
    });
  }

  void _onConsoleMessage(InAppWebViewController ctrl, ConsoleMessage msg) {
    debugPrint('WfwPage console [${msg.messageLevel}]: ${msg.message}');
  }

  // ---- Navigation ----

  Future<void> _goBack() async {
    final c = _controller;
    if (c == null) return;
    if (await c.canGoBack()) {
      setState(() => _loading = true);
      await c.goBack();
    }
  }

  Future<void> _goForward() async {
    final c = _controller;
    if (c == null) return;
    if (await c.canGoForward()) {
      setState(() => _loading = true);
      await c.goForward();
    }
  }

  Future<void> _openInBrowser() async {
    final c = _controller;
    if (c == null) return;
    final current = await c.getUrl();
    final uri = current ?? WebUri('https://wfw.scu.edu.cn/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = l10n.wfwTitle;

    if (OS.isHarmony) {
      return WebViewUnsupportedPage(title: title);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          setState(() => _loading = true);
          await c.goBack();
        } else if (mounted) {
          if (logicRootContext.mounted) Navigator.of(logicRootContext).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 152,
          centerTitle: true,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.close,
                  onPressed: () {
                    if (logicRootContext.mounted) {
                      Navigator.of(logicRootContext).pop();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: l10n.goBack,
                  onPressed: _canGoBack ? _goBack : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  tooltip: l10n.goForward,
                  onPressed: _canGoForward ? _goForward : null,
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refresh,
              onPressed: () {
                final c = _controller;
                if (c != null) {
                  setState(() => _loading = true);
                  c.reload();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: l10n.openInBrowser,
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Stack(
          children: [
            InAppWebView(
              onWebViewCreated: _onWebViewCreated,
              initialUrlRequest: URLRequest(url: WebUri('https://wfw.scu.edu.cn/')),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useWideViewPort: true,
                supportZoom: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
              ),
              onLoadStart: _onLoadStart,
              onLoadStop: _onLoadStop,
              onConsoleMessage: _onConsoleMessage,
              onReceivedError: (ctrl, request, error) {
                debugPrint('WfwPage error: ${error.description} (${error.type})');
                if ((request.isForMainFrame ?? false) && _errorHtmlTemplate.isNotEmpty) {
                  ctrl.loadData(data: _errorHtmlTemplate);
                }
              },
            ),
            if (_loading)
              Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
