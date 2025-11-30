// Simple, cross-platform visit image view helper.
// We avoid using dart:html or platformViewRegistry directly to keep the
// implementation compatible across SDK versions. For web this will use
// Image.network which renders a native <img> element in the browser.
import 'package:flutter/material.dart';

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
                ],
            );
        },
    );
}
