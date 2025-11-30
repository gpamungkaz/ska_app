# CORS Troubleshooting Checklist

## Masalah
Foto tidak dapat dimuat di web dengan error: `HTTP request failed, statusCode: 0`

## 🔴 PENTING: Masalah Ditemukan

**Domain baru (`https://ska.rupacobacoba.com`):**
- ❌ HTTP 404 - File foto TIDAK ADA di domain baru
- Foto hanya ada di domain lama (`https://ska-local.rupacobacoba.com`)

**Solusi:**
1. **Kembalikan API URL ke domain lama** (`https://ska-local.rupacobacoba.com`)
2. **Atau copy/sync file foto ke domain baru**

## Checklist Perbaikan

### 1. ✅ Verifikasi CORS Header Sudah Ditambahkan
```bash
curl -I "https://ska-local.rupacobacoba.com/storage/visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png"
```

**Harus menampilkan:**
```
HTTP/2 200
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, HEAD, OPTIONS
```

### 2. ✅ Clear Cloudflare Cache
**PENTING!** Jika menggunakan Cloudflare:
1. Login ke https://dash.cloudflare.com/
2. Pilih domain `ska-local.rupacobacoba.com`
3. Buka tab **Caching**
4. Klik **Purge Everything**
5. Tunggu 5-10 menit untuk cache ter-clear

### 3. ✅ Verifikasi di Browser
Buka browser console (F12) dan cek:
- Buka aplikasi di http://localhost:3000
- Klik detail kunjungan yang memiliki foto
- Buka DevTools → Console
- Cari error message

### 4. ✅ Test URL Langsung di Browser
Buka tab baru dan akses URL gambar langsung:
```
https://ska-local.rupacobacoba.com/storage/visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png
```

Jika gambar terbuka, berarti CORS header sudah bekerja.

### 5. ✅ Jika Masih Error - Gunakan Proxy Endpoint
Jika CORS header masih tidak bekerja, buat endpoint proxy di Laravel (lihat CORS_FIX_NEEDED.md Opsi 2).

## Langkah-Langkah Solusi

### Solusi 1: Tambahkan CORS Header (Recommended)

**Untuk Apache (.htaccess):**
```apache
<IfModule mod_headers.c>
    Header set Access-Control-Allow-Origin "*"
    Header set Access-Control-Allow-Methods "GET, HEAD, OPTIONS"
    Header set Access-Control-Allow-Headers "Content-Type, Authorization"
    Header set Access-Control-Max-Age "3600"
</IfModule>
```

**Untuk Nginx:**
```nginx
add_header 'Access-Control-Allow-Origin' '*' always;
add_header 'Access-Control-Allow-Methods' 'GET, HEAD, OPTIONS' always;
add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization' always;
```

### Solusi 2: Clear Cloudflare Cache
1. Masuk ke Cloudflare Dashboard
2. Purge Everything
3. Tunggu cache ter-clear

### Solusi 3: Gunakan Proxy Endpoint (Jika Opsi 1 & 2 Gagal)
Lihat CORS_FIX_NEEDED.md untuk membuat proxy endpoint.

## Testing

### Test 1: Curl dengan Headers
```bash
curl -I "https://ska-local.rupacobacoba.com/storage/visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png" | grep -i "access-control"
```

**Expected Output:**
```
access-control-allow-origin: *
access-control-allow-methods: GET, HEAD, OPTIONS
```

### Test 2: Reload Flutter App
Setelah menambahkan CORS header dan clear cache:
1. Refresh browser (Ctrl+F5 atau Cmd+Shift+R)
2. Buka detail kunjungan lagi
3. Foto seharusnya sudah bisa dimuat

### Test 3: Check Browser Console
Buka DevTools (F12) → Console dan cari error message.

## Jika Masih Tidak Berhasil

1. **Verifikasi CORS header sudah ditambahkan:**
   ```bash
   curl -v "https://ska-local.rupacobacoba.com/storage/visits/69hf5KUxNSre8rCUFKPOl1dzke0DNFyzlhdkiZn6.png" 2>&1 | grep -i "access-control"
   ```

2. **Clear Cloudflare cache lagi** (mungkin masih ter-cache)

3. **Gunakan Proxy Endpoint** sebagai alternatif

4. **Hubungi hosting/server admin** jika masalah persisten

## Referensi
- [MDN: CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
- [Cloudflare: Cache Control](https://support.cloudflare.com/hc/en-us/articles/200172516-Understanding-Cloudflare-s-CDN)
