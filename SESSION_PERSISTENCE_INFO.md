# Session Persistence - SKA App

## Status: ✅ SUDAH TERIMPLEMENTASI DENGAN BENAR

Session login untuk **semua role** (Marketing, Owner, dan **Sprinter**) sudah tersimpan secara otomatis dan persistent menggunakan `SharedPreferences`.

## Bagaimana Cara Kerjanya?

### 1. **Saat Login** (`login_screen.dart`)
Ketika user berhasil login (termasuk sprinter), data session disimpan:
```dart
await AuthStorage.saveSession(
  token: token,        // Token autentikasi dari server
  role: role.name,     // Role: 'sprinter', 'marketing', atau 'owner'
  name: displayName,   // Nama user
);
```

Data yang disimpan di `SharedPreferences`:
- `ska_auth_token` → Token autentikasi
- `ska_auth_role` → Role user (sprinter/marketing/owner)
- `ska_auth_name` → Nama user

### 2. **Saat Aplikasi Dibuka** (`splash_screen.dart`)
Setiap kali aplikasi dibuka, `SplashScreen` akan:
```dart
final session = await AuthStorage.readSession();
```

**Jika session ditemukan:**
- ✅ User langsung diarahkan ke dashboard sesuai role-nya
- ✅ Tidak perlu login ulang
- ✅ Token dan data user langsung tersedia

**Jika session tidak ditemukan atau invalid:**
- User diarahkan ke halaman login

### 3. **Saat Logout** (`sprinter_screen.dart`)
Ketika user menekan tombol logout:
```dart
await AuthStorage.clearSession();
```
Semua data session dihapus dan user diarahkan kembali ke login screen.

## File-File Terkait

### 1. `lib/services/auth_storage.dart`
Service untuk mengelola session menggunakan `SharedPreferences`:
- ✅ `saveSession()` - Menyimpan token, role, dan nama
- ✅ `readSession()` - Membaca session yang tersimpan
- ✅ `clearSession()` - Menghapus session (logout)

### 2. `lib/screens/splash_screen.dart`
Screen pertama yang dijalankan aplikasi:
- ✅ Membaca session yang tersimpan
- ✅ Memvalidasi role
- ✅ Redirect ke dashboard atau login

### 3. `lib/screens/login_screen.dart`
Screen login:
- ✅ Menyimpan session setelah login berhasil
- ✅ Mendukung semua role (marketing, owner, sprinter)

### 4. `lib/screens/sprinter_screen.dart`
Dashboard sprinter:
- ✅ Memiliki tombol logout
- ✅ Menampilkan konfirmasi sebelum logout
- ✅ Menghapus session saat logout

### 5. `lib/main.dart`
Entry point aplikasi:
- ✅ Memulai dari `SplashScreen`

## Testing Session Persistence

### Test Case 1: Login → Close App → Open App
1. ✅ Login sebagai sprinter
2. ✅ Close aplikasi (kill process)
3. ✅ Buka aplikasi lagi
4. ✅ **EXPECTED**: User langsung masuk ke dashboard sprinter tanpa login ulang

### Test Case 2: Login → Logout → Close App → Open App
1. ✅ Login sebagai sprinter
2. ✅ Klik tombol logout
3. ✅ Close aplikasi
4. ✅ Buka aplikasi lagi
5. ✅ **EXPECTED**: User harus login ulang (session sudah dihapus)

### Test Case 3: Login → Background → Foreground
1. ✅ Login sebagai sprinter
2. ✅ Minimize aplikasi (ke background)
3. ✅ Buka aplikasi lagi (ke foreground)
4. ✅ **EXPECTED**: User tetap di dashboard sprinter (session masih ada)

## Dependencies

Package yang digunakan:
```yaml
shared_preferences: ^2.2.2  # Untuk menyimpan data secara persistent
```

`SharedPreferences` menyimpan data di:
- **Android**: SharedPreferences
- **iOS**: NSUserDefaults
- **Web**: LocalStorage
- **Windows/Linux/macOS**: File system

## Keamanan

⚠️ **CATATAN PENTING:**
- Token disimpan dalam `SharedPreferences` yang **TIDAK terenkripsi**
- Untuk keamanan lebih tinggi, pertimbangkan menggunakan:
  - `flutter_secure_storage` untuk enkripsi token
  - Token expiration dan refresh token mechanism
  - Biometric authentication

## Kesimpulan

✅ **Session persistence sudah berfungsi dengan baik untuk semua role termasuk Sprinter**

User sprinter (dan role lainnya) **TIDAK perlu login ulang** setiap kali membuka aplikasi karena:
1. Token dan data user tersimpan di `SharedPreferences`
2. `SplashScreen` otomatis membaca session saat app dibuka
3. User langsung diarahkan ke dashboard sesuai role-nya

Satu-satunya cara session hilang adalah:
- User melakukan logout manual
- User menghapus data aplikasi dari settings
- User uninstall dan install ulang aplikasi

---
**Dibuat:** 14 Desember 2025
**Status:** VERIFIED ✅
