<div align="center">

# 🏪 WarungPintar Lite v2.0

**Aplikasi manajemen toko digital untuk UMKM Indonesia — didukung oleh AI.**

[![CI/CD](https://github.com/Fawwzrf/WarungPintar/actions/workflows/ci_cd.yaml/badge.svg)](https://github.com/Fawwzrf/WarungPintar/actions/workflows/ci_cd.yaml)
![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)
![Supabase](https://img.shields.io/badge/Supabase-Backend-3ecf8e?logo=supabase)
![Gemini](https://img.shields.io/badge/Google%20Gemini-AI%20Engine-4285F4?logo=google)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## 📌 Tentang Proyek

**WarungPintar Lite v2.0** adalah aplikasi manajemen toko kelontong dan UMKM yang dibangun di atas stack modern: **Flutter + Supabase + Google Gemini**. Proyek ini menggambarkan integrasi end-to-end antara aplikasi mobile dan layanan AI cloud — dari pengumpulan data transaksi real-time hingga menghasilkan laporan bisnis otomatis dalam Bahasa Indonesia menggunakan LLM.

### Masalah yang Diselesaikan
Mayoritas pemilik warung di Indonesia (64 juta UMKM) masih mencatat stok dan piutang pelanggan secara manual di buku tulis. WarungPintar menggantikan proses manual ini dengan sistem digital yang:
- Berjalan **offline-first** (tetap bisa digunakan tanpa internet)
- **Sinkron real-time** di antara beberapa perangkat (pemilik + kasir)
- Memberikan **rekomendasi AI** tentang kapan dan berapa banyak stok harus dibeli

---

## ✨ Fitur Utama

### 🤖 AI-Powered (via Google Gemini)
| Fitur | Deskripsi |
|-------|-----------|
| **Prediksi Restock Cerdas** | Menganalisis laju penjualan 30 hari & memprediksi kapan stok akan habis |
| **Laporan Tren Otomatis** | Menghasilkan narasi bisnis bulanan dalam Bahasa Indonesia |
| **Graceful AI Degradation** | *Rule-based fallback* otomatis jika kuota AI habis, menjaga UI tetap berjalan |

Kedua fitur AI berjalan di **Supabase Edge Functions (Deno/TypeScript)** — tidak ada komputasi AI di perangkat, menjaga konsumsi baterai dan RAM tetap rendah.

### 📦 Manajemen Inventaris
- CRUD produk lengkap dengan foto (Supabase Storage)
- Manajemen stok real-time via WebSocket (Supabase Realtime)
- Riwayat mutasi stok dengan aktor & timestamp
- Pencarian produk real-time (debounce 300ms)

### 💳 Buku Kasbon Digital
- Multi-item transactions dengan validasi batas kredit
- Status cicilan/pelunasan dengan riwayat pembayaran
- Pengingat via WhatsApp (deep link)

### 📊 Laporan & Ekspor
- Dashboard ringkasan dengan grafik penjualan 7 hari (fl_chart)
- Laporan penjualan & kasbon
- Ekspor ke **CSV** & **PDF** + share via WhatsApp

### 🔐 Auth & RBAC
- Supabase Auth (email/password) dengan JWT
- **Row Level Security** di database level — bukan hanya gate UI
- Dua peran: **Admin (Pemilik)** vs **Kasir** dengan hak akses berbeda
- Auto-logout setelah 1 jam tidak aktif

### 📶 Offline-First
- Cache lokal menggunakan **Hive** (NoSQL) yang diisolasi per user ID
- Indikator status koneksi real-time
- Fallback ke data cache saat tidak ada jaringan

---

## 🏗️ Arsitektur Sistem

```
┌────────────────────────────────────────────────────┐
│               Flutter App (Dart)                   │
│  Riverpod State │ Hive Cache │ Flutter Secure Storage│
└────────────────────┬───────────────────────────────┘
                     │ HTTPS / WebSocket
┌────────────────────▼───────────────────────────────┐
│                 SUPABASE CLOUD                      │
│  Auth │ PostgreSQL + RLS │ Realtime │ Edge Functions│
│                  Storage                           │
└────────────────────┬───────────────────────────────┘
                     │ HTTPS (server-side only)
              ┌──────▼──────┐
              │ Google Gemini│
              │   2.0 Flash  │
              └─────────────┘
```

## 🛠️ Tech Stack

| Layer | Teknologi |
|-------|-----------|
| Mobile Framework | Flutter (Dart) |
| State Management | flutter_riverpod |
| Backend & Database | Supabase (PostgreSQL + RLS) |
| Realtime | Supabase Realtime (WebSocket) |
| Auth | Supabase Auth + JWT + Flutter Secure Storage |
| AI Engine | Google Gemini 2.0 Flash (via Edge Functions) |
| Edge Functions | Deno (TypeScript) |
| Local Cache | Hive (NoSQL) |
| Charts | fl_chart |
| Export | pdf + csv + share_plus |
| CI/CD | GitHub Actions |

---

## 🚀 Cara Menjalankan

### Prasyarat
- Flutter SDK ≥ 3.9
- Akun [Supabase](https://supabase.com) (gratis)
- Google Gemini API Key (dari [Google AI Studio](https://aistudio.google.com))

### 1. Clone & Install
```bash
git clone https://github.com/Fawwzrf/WarungPintar.git
cd WarungPintar
flutter pub get
```

### 2. Setup Database Supabase
Jalankan SQL migration di Supabase SQL Editor:
```
sql/000_reset_and_rebuild.sql
sql/001_sales_and_expenses.sql
sql/002_member_management.sql
```

> **Penting:** Hapus trigger `on_auth_user_created` agar alur onboarding berjalan benar:
> ```sql
> DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
> ```

### 3. Deploy Edge Functions
```bash
supabase functions deploy restock-prediction
supabase functions deploy ai-monthly-report
```
Set secrets di Supabase Dashboard:
```
GEMINI_API_KEY=your_key_here
```

### 4. Jalankan Aplikasi
```bash
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=your_anon_key
```

---

## 🧪 Testing & CI/CD

```bash
flutter analyze   # 0 issues
flutter test      # 12 tests passed
```

CI/CD Pipeline di GitHub Actions otomatis menjalankan:
1. `flutter analyze` (linting)
2. `flutter test` (unit & widget tests)
3. `flutter build apk --release` (pada push ke `main`)

---

## 📁 Struktur Proyek

```
lib/
├── core/                   # Utilitas inti, autentikasi, & konfigurasi database
├── features/               # Arsitektur Feature-First (MVVM)
│   ├── dashboard/          # Layar utama & integrasi card prediksi AI
│   ├── debts/              # Manajemen pelanggan dan kasbon
│   ├── inventory/          # Manajemen produk dan pencatatan stok
│   ├── onboarding/         # Login dan pemilihan peran (Admin/Kasir)
│   ├── reports/            # Laporan keuangan & narasi otomatis Gemini AI
│   ├── sales/              # Point of Sale (PoS) kasir
│   └── settings/           # Pengaturan pengguna & karyawan
└── main.dart               # Entry point, routing, & tema Material 3 modern

supabase/functions/
├── restock-prediction/     # Edge Function: Prediksi stok (termasuk rule-based fallback)
└── ai-monthly-report/      # Edge Function: Laporan naratif bulanan (Gemini Flash)


sql/                        # Database migrations & RLS policies
test/                       # Unit & widget tests
```

---

## 📄 Lisensi

MIT License — bebas digunakan untuk portofolio dan pembelajaran.

---

<div align="center">
  Dibuat dengan ❤️ menggunakan Flutter & Supabase
</div>
