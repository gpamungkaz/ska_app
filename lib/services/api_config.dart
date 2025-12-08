import 'package:flutter/foundation.dart';

/// API configuration for different environments
///
/// This class automatically switches between development and production
/// API endpoints based on the build mode:
/// - Debug mode: Uses local development server
/// - Release mode (production APK): Uses production server
///
/// To change the production URL, update the _prodBaseUrl constant below.
class ApiConfig {
  // TODO: Replace with your actual production API URL
  static const String _devBaseUrl = 'https://ska-local.rupacobacoba.com';
  // static const String _devBaseUrl = 'https://ska.rupacobacoba.com'; // ← GANTI URL INI!
  static const String _prodBaseUrl = 'https://ska.rupacobacoba.com'; // ← GANTI URL INI!

  /// Get the base URL based on current environment
  static String get baseUrl {
    // In debug mode, use local development server
    // In release mode (production APK), use production server
    final url = kReleaseMode ? _prodBaseUrl : _devBaseUrl;

    // Debug logging
    if (kDebugMode) {
      print('🔧 API Config: Using ${kReleaseMode ? 'PRODUCTION' : 'DEVELOPMENT'} environment');
      print('🔧 API Base URL: $url');
    }

    return url;
  }

  /// Login endpoint
  static String get loginEndpoint => '$baseUrl/api/v1/login';

  /// Visits endpoint
  static String get visitsEndpoint => '$baseUrl/api/v1/visits';

  /// Dealers endpoint
  static String get dealersEndpoint => '$baseUrl/api/v1/dealers';

  /// Purchase Orders (SPK) endpoint
  static String get purchaseOrdersEndpoint => '$baseUrl/api/v1/purchase-orders';

  /// Body Types endpoint
  static String get bodyTypesEndpoint => '$baseUrl/api/v1/body-types';

  /// SPK (Purchase Order) endpoint
  static String get spkEndpoint => '$baseUrl/api/v1/spk';

  /// Other API endpoints can be added here as needed
}