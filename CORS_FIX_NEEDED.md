# CORS Issue - Foto Detail Kunjungan Tidak Terbuka di Web

## Masalah
Foto pada detail kunjungan tidak dapat terbuka ketika aplikasi diakses dari web browser. Error yang terjadi adalah CORS (Cross-Origin Resource Sharing) error.

**Error Message di Console:**
```
HTTP request failed, statusCode: 0
```

Status code 0 menunjukkan browser memblokir request karena CORS.

## Penyebab
Server API (`https://ska-local.rupacobacoba.com`) tidak mengirimkan header CORS yang diperlukan untuk mengizinkan browser memuat gambar dari domain lain.

### Verifikasi Masalah
```bash
curl -I "https://ska-local.rupacobacoba.com/storage/visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png"
```

Response tidak memiliki header `Access-Control-Allow-Origin`:
```
HTTP/2 200 
content-type: image/png
content-length: 82586
# ❌ Tidak ada Access-Control-Allow-Origin header
```

### Catatan Penting
- ✅ URL sudah benar: `/storage/visits/...`
- ✅ Server merespons dengan HTTP 200
- ✅ Gambar ada di server
- ❌ Tetapi browser menolak akses karena tidak ada CORS header

## Solusi

### Opsi 1: Tambahkan CORS Header di Server (Recommended)

#### Untuk File Statis (Storage/Public)
Tambahkan di `.htaccess` atau `public/.htaccess`:

```apache
<IfModule mod_headers.c>
    Header set Access-Control-Allow-Origin "*"
    Header set Access-Control-Allow-Methods "GET, HEAD, OPTIONS"
    Header set Access-Control-Allow-Headers "Content-Type, Authorization"
    Header set Access-Control-Max-Age "3600"
</IfModule>
```

#### Untuk Laravel API
Jika menggunakan Laravel 9+, pastikan middleware CORS sudah aktif:

```php
// config/cors.php
'paths' => ['api/*', 'storage/*'],
'allowed_methods' => ['*'],
'allowed_origins' => ['*'],
'allowed_headers' => ['*'],
'exposed_headers' => [],
'max_age' => 0,
'supports_credentials' => false,
```

#### Untuk Nginx
Tambahkan di server block:

```nginx
add_header 'Access-Control-Allow-Origin' '*' always;
add_header 'Access-Control-Allow-Methods' 'GET, HEAD, OPTIONS' always;
add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization' always;
add_header 'Access-Control-Max-Age' '3600' always;
```

#### Penting: Clear Cloudflare Cache
Jika menggunakan Cloudflare, **purge cache** setelah menambahkan CORS header:
1. Login ke Cloudflare dashboard
2. Pilih domain `ska-local.rupacobacoba.com`
3. Caching → Purge Everything
4. Tunggu beberapa menit

### Opsi 2: Buat Proxy Endpoint di Laravel (Alternatif)
Jika CORS header masih tidak bekerja, buat endpoint proxy di Laravel:

```php
// routes/api.php
Route::get('/proxy-image', function (Request $request) {
    $url = $request->query('url');
    
    if (!$url) {
        return response()->json(['error' => 'URL required'], 400);
    }
    
    try {
        $response = Http::get($url);
        
        return response($response->body())
            ->header('Content-Type', $response->header('Content-Type'))
            ->header('Access-Control-Allow-Origin', '*')
            ->header('Access-Control-Allow-Methods', 'GET, OPTIONS')
            ->header('Cache-Control', 'max-age=86400');
    } catch (\Exception $e) {
        return response()->json(['error' => 'Failed to fetch image'], 500);
    }
});
```

Kemudian di Flutter, ubah URL gambar:
```dart
// Dari: https://ska-local.rupacobacoba.com/storage/visits/...
// Menjadi: https://ska-local.rupacobacoba.com/api/v1/proxy-image?url=https://ska-local.rupacobacoba.com/storage/visits/...
```

### Opsi 3: Gunakan Data URL
Encode gambar sebagai base64 dan kirim sebagai data URL dalam response API.

## Verifikasi Perbaikan
Setelah menambahkan CORS header, response harus terlihat seperti:
```
HTTP/2 200 
content-type: image/png
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, OPTIONS
```

## Testing
```bash
# Test dengan curl
curl -I "https://ska-local.rupacobacoba.com/storage/visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png" | grep -i access-control

# Harus menampilkan:
# Access-Control-Allow-Origin: *
```

## Referensi
- [MDN: CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
- [Laravel CORS Package](https://github.com/fruitcake/laravel-cors)
