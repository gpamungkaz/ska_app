# Analisis Perbandingan Foto Selfie: Marketing vs Sprinter

## 📊 Perbandingan Struktur Data

### 1. **Data Kunjungan Marketing/Owner** (VisitData)

```json
{
  "dealer": {
    "name": "Dealer ABC",
    "address": "Jl. Example 123"
  },
  "customer": {
    "name": "John Doe",
    "phone": "08123456789"
  },
  "selfie": {
    "url": "https://example.com/storage/visits/selfie123.jpg",
    "thumbnail_url": "https://example.com/storage/visits/thumb_selfie123.jpg",
    "captured_at": "2025-12-14T08:45:00.000000Z",
    "label": "Dokumentasi Kunjungan"
  },
  "latitude": "-7.78730223",
  "longitude": "110.31283434",
  "visit_type": "visit",
  "status": "completed",
  "notes": "Kunjungan berjalan lancar",
  "created_at": "2025-12-14T08:45:00.000000Z"
}
```

**Field foto selfie:**
- `selfie.url` atau `selfie_url` → URL full resolution
- `selfie.thumbnail_url` → URL thumbnail (opsional)
- `selfie.captured_at` → Timestamp foto diambil
- `selfie.label` → Label deskripsi foto

---

### 2. **Data Presensi Sprinter** (AttendanceData)

```json
{
  "id": 2,
  "user_id": 21,
  "photo": "attendances/693e790c405a5_1765701900.jpg",
  "latitude": "-7.78730223",
  "longitude": "110.31283434",
  "status": "present",
  "created_at": "2025-12-14T08:45:00.000000Z",
  "updated_at": "2025-12-14T08:45:00.000000Z",
  "user": {
    "id": 21,
    "name": "Sprinter",
    "email": "sprinter@ska.com"
  }
}
```

**Field foto selfie:**
- `photo` → Path/filename foto (BUKAN full URL)
- Tidak ada `thumbnail_url`
- Tidak ada `captured_at` terpisah (gunakan `created_at`)
- Tidak ada `label` khusus foto

---

## 🔍 Perbedaan Utama

| Aspek | Marketing/Owner (Visit) | Sprinter (Attendance) |
|-------|------------------------|----------------------|
| **Field Foto** | `selfie.url` atau `selfie_url` | `photo` |
| **Format URL** | Full URL lengkap dengan base URL | Hanya path relatif |
| **Thumbnail** | ✅ Ada (`selfie.thumbnail_url`) | ❌ Tidak ada |
| **Timestamp Foto** | ✅ Ada (`selfie.captured_at`) | ❌ Gunakan `created_at` |
| **Label Foto** | ✅ Ada (`selfie.label`) | ❌ Tidak ada (default: "Foto Selfie") |
| **Struktur** | Nested object `selfie: {...}` | Flat field `photo` |
| **Context Data** | Dealer, Customer, Visit Info | User info, Status presensi |

---

## 🛠️ Implementasi untuk Sprinter

### A. Model Data (AttendanceData) - Sudah Ada ✅

```dart
class AttendanceData {
  const AttendanceData({
    required this.id,
    required this.employeeName,
    required this.attendanceDate,
    this.photoUrl,  // Ini adalah path, bukan full URL
    this.latitude,
    this.longitude,
  });

  final int id;
  final String employeeName;
  final String attendanceDate; // ISO 8601 string
  final String? photoUrl;      // Path: "attendances/xxxxx.jpg"
  final double? latitude;
  final double? longitude;

  factory AttendanceData.fromJson(Map<String, dynamic> json) {
    return AttendanceData(
      id: json['id'] as int? ?? 0,
      employeeName: json['employee_name']?.toString() ?? 
                    json['user']?['name'] ?? '-',
      attendanceDate: json['attendance_date']?.toString() ??
                     json['created_at']?.toString() ?? '-',
      photoUrl: json['photo']?.toString() ?? 
               json['photo_url']?.toString(),
      latitude: (json['latitude'] is num)
          ? (json['latitude'] as num).toDouble()
          : double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: (json['longitude'] is num)
          ? (json['longitude'] as num).toDouble()
          : double.tryParse(json['longitude']?.toString() ?? ''),
    );
  }
}
```

### B. Konversi Photo Path ke Full URL

Sprinter mengirim `photo: "attendances/693e790c405a5_1765701900.jpg"` yang merupakan **path relatif**.

**Perlu dikonversi menjadi:**
```
https://yourdomain.com/storage/attendances/693e790c405a5_1765701900.jpg
```

**Implementasi:**

```dart
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
```

### C. Widget untuk Menampilkan Foto Presensi Sprinter

Mirip dengan `_VisitSelfieSection`, tapi disesuaikan untuk struktur data sprinter:

```dart
class _AttendanceSelfieSection extends StatefulWidget {
  const _AttendanceSelfieSection({
    required this.attendance,
    required this.authToken,
  });

  final AttendanceData attendance;
  final String authToken;

  @override
  State<_AttendanceSelfieSection> createState() => 
      _AttendanceSelfieSectionState();
}

class _AttendanceSelfieSectionState extends State<_AttendanceSelfieSection> {
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  String? _getFullPhotoUrl() {
    final photoPath = widget.attendance.photoUrl;
    if (photoPath == null || photoPath.isEmpty) return null;
    
    // Jika sudah full URL
    if (photoPath.startsWith('http://') || photoPath.startsWith('https://')) {
      return photoPath;
    }
    
    // Konversi path ke full URL
    final baseUrl = ApiConfig.baseUrl;
    return '$baseUrl/storage/$photoPath';
  }

  Widget _buildWebImageWidget(String imageUrl) {
    // Untuk web, gunakan proxy endpoint untuk handle CORS
    final proxyUrl = _getProxyUrl(imageUrl);

    return Image.network(
      proxyUrl,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;

        final progress = loadingProgress.expectedTotalBytes != null
            ? loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!
            : 0.0;

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey[300],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.green,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorPlaceholder('Foto tidak dapat dimuat.');
      },
    );
  }

  String _getProxyUrl(String imageUrl) {
    try {
      String path = imageUrl;

      // Extract path setelah /storage/
      if (imageUrl.contains('/storage/')) {
        final parts = imageUrl.split('/storage/');
        if (parts.length > 1) {
          path = parts[1];
        }
      }

      // Buat proxy URL
      final baseUrl = ApiConfig.baseUrl;
      return '$baseUrl/api/v1/proxy-image?path=$path';
    } catch (e) {
      return imageUrl;
    }
  }

  Future<void> _loadImage() async {
    final fullUrl = _getFullPhotoUrl();
    
    if (fullUrl == null || fullUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'URL foto tidak tersedia';
      });
      return;
    }

    // Pada web, gunakan native <img> tag (hindari CORS dengan XHR)
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(fullUrl),
        headers: {'Authorization': 'Bearer ${widget.authToken}'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _imageBytes = response.bodyBytes;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        });
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $error';
      });
    }
  }

  Widget _buildErrorPlaceholder(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timestamp = widget.attendance.attendanceDate;
    
    Widget mediaWidget;
    final fullUrl = _getFullPhotoUrl();

    if (kIsWeb && fullUrl != null && fullUrl.isNotEmpty) {
      mediaWidget = _buildWebImageWidget(fullUrl);
    } else if (_isLoading) {
      mediaWidget = Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Colors.green,
          ),
        ),
      );
    } else if (_imageBytes != null) {
      mediaWidget = Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _imageBytes!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
          if (timestamp != null && timestamp != '-')
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatRelativeTime(timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    } else {
      mediaWidget = _buildErrorPlaceholder(
        _errorMessage ?? 'Foto selfie gagal dimuat.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Foto Selfie',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ) ?? const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(
              maxHeight: 600,
              minHeight: 300,
            ),
            color: Colors.black12,
            child: mediaWidget,
          ),
        ),
      ],
    );
  }
}
```

### D. Integrasi ke Detail Sheet Presensi

Tambahkan section foto di `_AttendanceDetailSheet`:

```dart
// Di dalam _AttendanceDetailSheet.build()
children: [
  // ... field lainnya ...
  
  // Foto Selfie Section
  if (attendance.photoUrl != null && attendance.photoUrl!.isNotEmpty) ...[
    const SizedBox(height: 28),
    _AttendanceSelfieSection(
      attendance: attendance,
      authToken: authToken,
    ),
  ],
  
  // Location Map Section
  if (hasLocation) ...[
    const SizedBox(height: 28),
    _AttendanceMapView(
      latitude: attendance.latitude!,
      longitude: attendance.longitude!,
    ),
  ],
]
```

---

## 📝 Checklist Implementasi

### ✅ Yang Sudah Ada (Sprinter Screen)
- [x] Model `AttendanceData` dengan field `photoUrl`
- [x] Parsing JSON dari API attendance
- [x] Detail sheet untuk attendance (`_AttendanceDetailSheet`)
- [x] Map view untuk lokasi
- [x] Format timestamp dengan `formatRelativeTime()`

### 🔨 Yang Perlu Ditambahkan
- [ ] Method `fullPhotoUrl` di `AttendanceData` untuk konversi path
- [ ] Widget `_AttendanceSelfieSection` untuk menampilkan foto
- [ ] CORS proxy handling untuk web (seperti di visit)
- [ ] Loading progress indicator saat foto dimuat
- [ ] Error handling untuk foto gagal dimuat
- [ ] Timestamp overlay di foto (opsional)
- [ ] Zoom/fullscreen foto saat di-tap (opsional)

---

## 🎨 Design Differences

### Marketing/Owner Visit Detail:
- Purple theme (#667eea, #764ba2, deepPurple)
- Title: "Detail Kunjungan"
- Context: Dealer, Customer, Visit type
- Label: Bisa custom dari `selfie.label`

### Sprinter Attendance Detail:
- Green theme (#11998e, #38ef7d, Colors.green)
- Title: "Detail Presensi"
- Context: Employee name, Status (present)
- Label: Fixed "Foto Selfie"

---

## 🔧 URL Construction Examples

### Marketing/Owner (Visit):
```
Input:  selfie.url = "visits/12345_selfie.jpg"
Output: https://yourdomain.com/storage/visits/12345_selfie.jpg
```

### Sprinter (Attendance):
```
Input:  photo = "attendances/693e790c405a5_1765701900.jpg"
Output: https://yourdomain.com/storage/attendances/693e790c405a5_1765701900.jpg
```

**Pattern:**
```dart
final fullUrl = '${ApiConfig.baseUrl}/storage/${photoPath}';
```

---

## 🚀 Next Steps

1. **Tambahkan helper method** di `AttendanceData`:
   ```dart
   String? get fullPhotoUrl => /* konversi logic */;
   bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;
   ```

2. **Buat widget `_AttendanceSelfieSection`** 
   - Copy pattern dari `_VisitSelfieSection`
   - Sesuaikan dengan green theme
   - Gunakan `fullPhotoUrl` untuk load image

3. **Update `_AttendanceDetailSheet`**
   - Tambahkan section foto setelah info presensi
   - Sebelum map location

4. **Test di platform berbeda**
   - Android: Direct HTTP load
   - iOS: Direct HTTP load
   - Web: Gunakan proxy endpoint untuk CORS

5. **Handle edge cases**
   - Photo null/empty
   - Invalid photo path
   - Network error
   - CORS error di web

---

**Dibuat:** 14 Desember 2025
**Status:** READY FOR IMPLEMENTATION 🚀
