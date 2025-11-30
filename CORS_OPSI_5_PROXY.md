# Opsi 5: Proxy Endpoint di Backend (Solusi Terbaik)

## Konsep
Membuat endpoint API di backend Laravel yang berfungsi sebagai proxy untuk mengambil gambar. Endpoint ini akan menambahkan CORS header secara otomatis.

## Implementasi di Laravel

### Step 1: Buat Controller Baru
```bash
php artisan make:controller ImageProxyController
```

### Step 2: Tambahkan Logic di Controller
```php
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;

class ImageProxyController extends Controller
{
    /**
     * Proxy image endpoint
     * 
     * Usage: GET /api/v1/proxy-image?path=visits/filename.png
     */
    public function proxyImage(Request $request)
    {
        $path = $request->query('path');
        
        if (!$path) {
            return response()->json(['error' => 'Path parameter required'], 400);
        }
        
        try {
            // Get file from storage
            if (!Storage::disk('public')->exists($path)) {
                return response()->json(['error' => 'File not found'], 404);
            }
            
            $fileContent = Storage::disk('public')->get($path);
            $mimeType = Storage::disk('public')->mimeType($path);
            
            return response($fileContent)
                ->header('Content-Type', $mimeType)
                ->header('Access-Control-Allow-Origin', '*')
                ->header('Access-Control-Allow-Methods', 'GET, OPTIONS')
                ->header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
                ->header('Cache-Control', 'max-age=86400, public');
                
        } catch (\Exception $e) {
            return response()->json(['error' => 'Failed to fetch image'], 500);
        }
    }
}
```

### Step 3: Tambahkan Route
```php
// routes/api.php
Route::get('/v1/proxy-image', [ImageProxyController::class, 'proxyImage']);
```

## Implementasi di Flutter

### Step 1: Buat Helper Function
```dart
// lib/utils/image_url_helper.dart

class ImageUrlHelper {
  static String proxyUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return '';
    
    // Jika sudah full URL, extract path-nya
    String path = imagePath;
    if (imagePath.contains('/storage/')) {
      path = imagePath.split('/storage/').last;
    }
    
    // Gunakan proxy endpoint
    final baseUrl = ApiConfig.baseUrl;
    return '$baseUrl/api/v1/proxy-image?path=$path';
  }
}
```

### Step 2: Update Image Loading di home_screen.dart
```dart
// Di _VisitSelfieSection.build()

if (kIsWeb && cleanUrl != null && cleanUrl.isNotEmpty) {
    // Use proxy endpoint for CORS handling
    final proxyUrl = ImageUrlHelper.proxyUrl(cleanUrl);
    
    mediaWidget = Image.network(
        proxyUrl,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
            if (kDebugMode) {
                print('🔧 [Image.network error] Proxy URL: $proxyUrl');
                print('🔧 [Image.network error] Error: $error');
            }
            return _VisitPlaceholderCard(
                icon: Icons.broken_image_outlined,
                message: 'Foto tidak dapat dimuat.',
            );
        },
    );
}
```

## Keuntungan Opsi 5

✅ **Tidak perlu mengubah server configuration**
✅ **CORS header ditambahkan di endpoint, bukan di static file**
✅ **Bisa cache di backend**
✅ **Lebih aman (bisa add authentication)**
✅ **Bisa add logging/monitoring**
✅ **Bekerja di semua domain**

## Testing

### Test 1: Verifikasi Endpoint
```bash
curl -I "https://ska-local.rupacobacoba.com/api/v1/proxy-image?path=visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png"
```

**Expected:**
```
HTTP/2 200
Content-Type: image/png
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, OPTIONS
```

### Test 2: Buka di Browser
```
https://ska-local.rupacobacoba.com/api/v1/proxy-image?path=visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png
```

Gambar harus terbuka tanpa error.

### Test 3: Test di Flutter Web
1. Update `_devBaseUrl` ke `https://ska-local.rupacobacoba.com`
2. Jalankan `flutter run -d chrome --web-port=3000`
3. Buka detail kunjungan
4. Foto seharusnya sudah terbuka

## Troubleshooting

### Error: File not found
- Pastikan path benar: `visits/filename.png`
- Pastikan file ada di `storage/app/public/visits/`

### Error: CORS masih error
- Pastikan endpoint sudah di-deploy
- Clear browser cache (Ctrl+F5)
- Check console untuk melihat exact error

### Performance Issue
- Tambahkan caching di controller
- Gunakan CDN untuk image proxy
- Optimize image size

## Referensi
- [Laravel Storage](https://laravel.com/docs/storage)
- [Laravel HTTP Client](https://laravel.com/docs/http-client)
- [CORS Headers](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
