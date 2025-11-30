import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Non-web implementation: fall back to Image.network with a simple
/// loading/error UI.
Widget visitImageView(String imageUrl, String viewType) {
  return Image.network(
    imageUrl,
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return const Center(child: CircularProgressIndicator());
    },
    errorBuilder: (context, error, stackTrace) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 8),
          const Text('Gambar tidak dapat dimuat.'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              final uri = Uri.tryParse(imageUrl);
              if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: const Text('Buka di tab baru'),
          ),
        ],
      );
    },
  );
}
