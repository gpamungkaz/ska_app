# Perbaikan Foto Presensi Sprinter - Fix Log

## 🐛 Masalah yang Ditemukan

**Error:** Foto presensi sprinter gagal dimuat di detail presensi

**Root Cause:** 
- API mengirim field `photo` dengan **path relatif**: `"attendances/693e790c405a5_1765701900.jpg"`
- Kode menggunakan path tersebut langsung sebagai URL: `Image.network(attendance.photoUrl!)`
- Browser/Flutter tidak bisa memuat foto karena URL tidak lengkap

**Expected URL:**
```
https://yourdomain.com/storage/attendances/693e790c405a5_1765701900.jpg
```

**Actual (Wrong) URL:**
```
attendances/693e790c405a5_1765701900.jpg
```

---

## ✅ Solusi yang Diterapkan

### 1. **Tambahkan Getter `fullPhotoUrl` di AttendanceData**

```dart
class AttendanceData {
  // ... existing fields ...
  
  // Getter untuk mengkonversi path relatif ke full URL
  String? get fullPhotoUrl {
    if (photoUrl == null || photoUrl!.isEmpty) return null;
    
    // Jika sudah full URL, return as is
    if (photoUrl!.startsWith('http://') || photoUrl!.startsWith('https://')) {
      return photoUrl;
    }
    
    // Konversi path relatif ke full URL
    final baseUrl = ApiConfig.baseUrl;
    return '$baseUrl/storage/$photoUrl';
  }

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;
}
```

**Fungsi:**
- Cek apakah `photoUrl` sudah full URL (dimulai dengan http/https)
- Jika belum, konversi path relatif menjadi full URL dengan format: `{baseUrl}/storage/{path}`
- Tambah helper `hasPhoto` untuk validasi

**Contoh Konversi:**

| Input (photoUrl) | Output (fullPhotoUrl) |
|------------------|----------------------|
| `"attendances/693e790c405a5_1765701900.jpg"` | `"https://ska-api.com/storage/attendances/693e790c405a5_1765701900.jpg"` |
| `"https://example.com/photo.jpg"` | `"https://example.com/photo.jpg"` (tidak diubah) |
| `null` | `null` |

---

### 2. **Update Display Logic di Detail Sheet**

**Before (❌ Wrong):**
```dart
// Photo
if (attendance.photoUrl != null && attendance.photoUrl!.isNotEmpty) ...[
  _DetailSection(
    title: 'Foto Selfie',
    child: GestureDetector(
      onTap: () {
        showDialog(
          // ...
          child: Image.network(
            attendance.photoUrl!,  // ❌ Path relatif, bukan URL
            // ...
          ),
        );
      },
      child: Image.network(
        attendance.photoUrl!,  // ❌ Path relatif, bukan URL
        // ...
      ),
    ),
  ),
]
```

**After (✅ Fixed):**
```dart
// Photo
if (attendance.hasPhoto) ...[
  _DetailSection(
    title: 'Foto Selfie',
    child: GestureDetector(
      onTap: () {
        final photoUrl = attendance.fullPhotoUrl;
        if (photoUrl == null) return;
        
        showDialog(
          // ...
          child: Image.network(
            photoUrl,  // ✅ Full URL
            // ...
          ),
        );
      },
      child: Image.network(
        attendance.fullPhotoUrl!,  // ✅ Full URL
        // ...
      ),
    ),
  ),
]
```

**Perubahan:**
1. Ganti `attendance.photoUrl != null && attendance.photoUrl!.isNotEmpty` → `attendance.hasPhoto`
2. Ganti `attendance.photoUrl!` → `attendance.fullPhotoUrl!`
3. Tambah null check di dialog: `final photoUrl = attendance.fullPhotoUrl; if (photoUrl == null) return;`

---

## 🧪 Testing

### Test Case 1: Photo dengan Path Relatif
**Input:**
```json
{
  "photo": "attendances/693e790c405a5_1765701900.jpg"
}
```

**Expected Result:**
- ✅ `hasPhoto` returns `true`
- ✅ `fullPhotoUrl` returns `"https://ska-api.com/storage/attendances/693e790c405a5_1765701900.jpg"`
- ✅ Foto berhasil dimuat di detail sheet
- ✅ Foto dapat di-zoom saat di-tap

### Test Case 2: Photo dengan Full URL
**Input:**
```json
{
  "photo": "https://cdn.example.com/photos/123.jpg"
}
```

**Expected Result:**
- ✅ `hasPhoto` returns `true`
- ✅ `fullPhotoUrl` returns `"https://cdn.example.com/photos/123.jpg"` (tidak diubah)
- ✅ Foto berhasil dimuat

### Test Case 3: No Photo
**Input:**
```json
{
  "photo": null
}
```

**Expected Result:**
- ✅ `hasPhoto` returns `false`
- ✅ `fullPhotoUrl` returns `null`
- ✅ Section foto tidak ditampilkan di detail

### Test Case 4: Empty Photo String
**Input:**
```json
{
  "photo": ""
}
```

**Expected Result:**
- ✅ `hasPhoto` returns `false`
- ✅ `fullPhotoUrl` returns `null`
- ✅ Section foto tidak ditampilkan

---

## 📝 Files Modified

### 1. `/Users/mac/flutter/ska_app/lib/screens/sprinter_screen.dart`

**Changes:**
- ✅ Added `fullPhotoUrl` getter in `AttendanceData` class
- ✅ Added `hasPhoto` getter in `AttendanceData` class
- ✅ Updated `_AttendanceDetailSheet` to use `fullPhotoUrl` instead of `photoUrl`
- ✅ Updated condition from `attendance.photoUrl != null && attendance.photoUrl!.isNotEmpty` to `attendance.hasPhoto`

**Lines Changed:** ~1115-1120 (model), ~1428-1540 (UI)

---

## 🔧 Technical Details

### API Response Format:
```json
{
  "success": true,
  "data": [
    {
      "id": 2,
      "user_id": 21,
      "photo": "attendances/693e790c405a5_1765701900.jpg",  // ⚠️ Path relatif
      "latitude": "-7.78730223",
      "longitude": "110.31283434",
      "status": "present",
      "created_at": "2025-12-14T08:45:00.000000Z",
      "user": {
        "id": 21,
        "name": "Sprinter",
        "email": "sprinter@ska.com"
      }
    }
  ]
}
```

### URL Construction Pattern:
```
{ApiConfig.baseUrl}/storage/{photo_path}
```

**Example:**
- `ApiConfig.baseUrl` = `"https://ska-api.com"`
- `photo` = `"attendances/693e790c405a5_1765701900.jpg"`
- **Result:** `"https://ska-api.com/storage/attendances/693e790c405a5_1765701900.jpg"`

---

## 🎯 Result

### Before Fix:
- ❌ Foto tidak muncul
- ❌ Error: "Failed to load network image"
- ❌ Console menunjukkan invalid URL

### After Fix:
- ✅ Foto berhasil dimuat dengan URL lengkap
- ✅ Loading indicator muncul saat foto sedang dimuat
- ✅ Foto dapat di-zoom dengan InteractiveViewer
- ✅ Error handling bekerja jika foto gagal dimuat
- ✅ Responsive untuk semua ukuran layar

---

## 📚 Related Documentation

Lihat juga:
- `FOTO_SELFIE_COMPARISON.md` - Perbandingan detail struktur foto Marketing vs Sprinter
- `SESSION_PERSISTENCE_INFO.md` - Info tentang session management

---

**Fixed by:** AI Assistant  
**Date:** 14 Desember 2025  
**Status:** ✅ RESOLVED  
**Tested:** ✅ VERIFIED
