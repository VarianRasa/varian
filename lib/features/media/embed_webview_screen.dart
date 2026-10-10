import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:webview_flutter/webview_flutter.dart';

class EmbedWebviewScreen extends StatefulWidget {
  final String url;
  final String title;

  const EmbedWebviewScreen({super.key, required this.url, required this.title});

  @override
  State<EmbedWebviewScreen> createState() => _EmbedWebviewScreenState();
}

class _EmbedWebviewScreenState extends State<EmbedWebviewScreen> {
  WebViewController? _controller;
  bool _loading = true;

  bool get _hasEmbeddedWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backgroundColor = context.appTokens.canvas;
    final existingController = _controller;
    if (existingController != null) {
      unawaited(existingController.setBackgroundColor(backgroundColor));
      return;
    }
    if (!_hasEmbeddedWebView) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(backgroundColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return UiPageScaffold(
      title: Text(
        widget.title.toUpperCase(),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        onPressed: () => Navigator.of(context).maybePop(),
        tooltip: 'Back',
      ),
      actions: [
        if (_controller != null) ...[
          UiIconButton(
            icon: Icons.arrow_back,
            onPressed: () => _controller!.goBack(),
            tooltip: 'Back in page',
          ),
          UiIconButton(
            icon: Icons.arrow_forward,
            onPressed: () => _controller!.goForward(),
            tooltip: 'Forward in page',
          ),
          UiIconButton(
            icon: Icons.refresh,
            onPressed: () => _controller!.reload(),
            tooltip: 'Reload page',
          ),
        ],
        UiIconButton(
          icon: Icons.open_in_new,
          onPressed: () => launchUrl(Uri.parse(widget.url)),
          tooltip: 'Open in new browser tab',
        ),
      ],
      child: !_hasEmbeddedWebView
          ? Center(
              child: Padding(
                padding: AppResponsive.pagePadding(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 64, color: tokens.accent),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      widget.url,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    UiButton(
                      onPressed: () => launchUrl(Uri.parse(widget.url)),
                      prefix: const Icon(Icons.open_in_new, size: 16),
                      child: const Text('OPEN EXTERNAL LINK'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                if (_controller != null)
                  WebViewWidget(controller: _controller!),
                if (_loading)
                  const Center(
                    child: UiProgressIndicator(
                      semanticsLabel: 'Loading embedded page',
                    ),
                  ),
              ],
            ),
    );
  }
}
