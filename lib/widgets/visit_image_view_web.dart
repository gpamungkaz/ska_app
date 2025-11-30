import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui' as ui; // Web-only

/// Web implementation: registers a view factory and returns an HtmlElementView
/// that renders a native <img> element for better browser behavior.
Widget visitImageView(String imageUrl, String viewType) {
  try {
    // registerViewFactory is only available on web. Ignore errors if
    // already registered.
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = imageUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';
      return img;
    });
  } catch (_) {}

  return HtmlElementView(viewType: viewType);
}
