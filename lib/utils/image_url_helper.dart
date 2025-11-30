import 'package:flutter/foundation.dart';
import '../services/api_config.dart';

/// Helper class untuk menghandle image URLs dengan proxy
class ImageUrlHelper {
  /// Convert image URL ke proxy URL untuk mengatasi CORS
  /// 
  /// Contoh:
  /// Input: https://ska-local.rupacobacoba.com/storage/visits/abc123.png
  /// Output: https://ska-local.rupacobacoba.com/api/v1/proxy-image?path=visits/abc123.png
  static String toProxyUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return '';
    
    try {
      // Extract path dari URL
      String path = imageUrl;
      
      // Jika URL mengandung /storage/, extract path setelah /storage/
      if (imageUrl.contains('/storage/')) {
        final parts = imageUrl.split('/storage/');
        if (parts.length > 1) {
          path = parts[1];
        }
      }
      
      // Jika masih full URL, extract path-nya
      if (path.contains('http')) {
        final uri = Uri.parse(path);
        path = uri.path.replaceFirst('/storage/', '');
      }
      
      // Buat proxy URL
      final baseUrl = ApiConfig.baseUrl;
      final proxyUrl = '$baseUrl/api/v1/proxy-image?path=$path';
      
      if (kDebugMode) {
        print('🔧 [ImageUrlHelper] Original URL: $imageUrl');
        print('🔧 [ImageUrlHelper] Proxy URL: $proxyUrl');
      }
      
      return proxyUrl;
    } catch (e) {
      if (kDebugMode) {
        print('🔧 [ImageUrlHelper] Error converting URL: $e');
      }
      return imageUrl;
    }
  }
  
  /// Check apakah URL sudah proxy URL
  static bool isProxyUrl(String url) {
    return url.contains('/api/v1/proxy-image');
  }
}
