# Puskesmas Scraper

Paket instalasi aplikasi scraping SIMPUS, penyimpanan hasil, dan pengiriman ke API. Scraping per kunjungan dan laporan berjalan di binary Rust yang sudah dikompilasi di dalam image Docker. Python hanya menjalankan login browser Scrapling, sehingga kode Python yang disertakan hanya untuk login. Source Rust dan compiler Rust tidak disertakan.

Langkah instalasi lengkap ada di `PANDUAN_DEPLOY.md`.

## Prasyarat

- Docker Engine/Desktop dengan Docker Compose v2.
- Image Linux/amd64; untuk pilot gunakan RAM 4 GB, 2 vCPU, dan disk 40 GB sebagai titik awal.
- Koneksi keluar ke portal SIMPUS dan API tujuan, serta provider LLM bila memakai pencocokan header otomatis.
- VPS publik: domain yang Anda kuasai, DNS A menuju IP VPS, serta port 80/443 untuk HTTPS.

Jika Docker belum terpasang pada Ubuntu, ikuti [panduan resmi Docker](https://docs.docker.com/engine/install/ubuntu/).

## Unduh image

Unduh empat aset dari [GitHub Release](https://github.com/Juxtalabs/simpus-sphere-enterprise/releases/tag/v0.1.2):

- `puskesmas-scraper-rust-hybrid.tar.gz`
- `puskesmas-scraper-deployment.zip`
- `SHA256SUMS`
- `release-manifest.json`

Di Linux, dari direktori unduhan:

```sh
sha256sum --check SHA256SUMS
docker image load --input puskesmas-scraper-rust-hybrid.tar.gz
unzip puskesmas-scraper-deployment.zip
cd puskesmas-scraper
```

Semua checksum harus menampilkan `OK`. Alternatif ZIP: clone repository ini untuk memperoleh file deployment, kemudian tetap unduh dan muat image dari release. Jangan jalankan build; repository ini tidak memuat source Rust.

## Instalasi VPS

```sh
sh deploy.sh prepare
nano .env.local
```

Pertahankan `POSTGRES_PASSWORD` acak yang sudah dibuat. Sesuaikan:

```dotenv
WEB_PORT=3003
COOKIE_SECURE=true
ALLOW_PRIVATE_DESTINATIONS=false
SYSTEM_MAX_CONCURRENT_JOBS=1
APP_MEMORY_LIMIT=2g
```

Nama domain bebas: domain utama atau subdomain, tanpa kewajiban awalan tertentu. DNS harus mengarah ke VPS. Jangan membagikan `.env.local`.

Buat administrator melalui terminal VPS:

```sh
sh deploy.sh init
```

Isi username pilihan Anda dan password minimal 12 karakter saat diminta; password tidak ditampilkan. Akun disimpan di database instalasi, tanpa akun atau password bawaan. Jika username sudah ada, perintah ini memperbarui password dan mengeluarkan semua sesi akun tersebut; peran tetap sama kecuali ditambahkan `--admin`.

```sh
sh deploy.sh up
sh deploy.sh status
sh deploy.sh doctor
```

Aplikasi dan database terikat ke loopback, jadi HTTPS disediakan reverse proxy Anda, misalnya nginx dengan certbot. Arahkan domain ke `http://127.0.0.1:3003` dan pertahankan `COOKIE_SECURE=true`, lalu buka `https://` diikuti domain Anda. Jangan membuka port 5435, 3003, atau 8111 ke internet.

## Menjalankan lokal

Linux/macOS: jalankan `sh deploy.sh prepare`, lalu atur `.env.local` menjadi `WEB_PORT=3002`, `COOKIE_SECURE=false`, dan `ALLOW_PRIVATE_DESTINATIONS=true` bila memakai dummy. Setelah `sh deploy.sh init`, jalankan `sh deploy.sh local`. Buka `http://localhost:3002`.

PowerShell, setelah image dimuat dan paket diekstrak:

```powershell
$dbPassword = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
@("POSTGRES_PASSWORD=$dbPassword", 'WEB_PORT=3002', 'COOKIE_SECURE=false', 'ALLOW_PRIVATE_DESTINATIONS=true') | Set-Content -Encoding utf8 .env.local
Remove-Variable dbPassword
docker compose --env-file .env.local up -d --wait postgres
docker compose --env-file .env.local run --rm app init --username admin
docker compose --env-file .env.local --profile test up -d --no-build --wait --wait-timeout 180
```

Perintah `init` meminta dan mengonfirmasi password secara tersembunyi. Jangan ulangi pembuatan `.env.local` pada instalasi yang sudah memiliki database. Dummy lokal tersedia di `http://localhost:8111`; dari aplikasi gunakan `http://dummy:8110/ingest`. Dummy ditujukan untuk data sintetis.

## Penggunaan

1. Login; Admin dapat membuat akun tambahan melalui Kelola akun.
2. Tambahkan Puskesmas dan kredensial SIMPUS yang diizinkan.
3. Jalankan scraping per tanggal; lihat progres pada Scrape Jobs dan data pada Reports per layanan atau Pasien per NIK.
4. Tambahkan tujuan API, lalu kirim hasil melalui Sync ke API.
5. Atur Cron untuk scraping, POST, scraping lalu POST, atau scraping laporan lalu POST. Jadwal yang mengirim mengambil ulang sendiri tanggal yang gagal atau belum lengkap dalam 7 hari terakhir. LLM tidak diperlukan untuk scraping rutin.

Hasil, jobs, jadwal, dan tujuan API dipisahkan per akun. Puskesmas dan konfigurasi LLM digunakan bersama dalam satu instalasi. Akun lokal tidak otomatis tersedia di VPS.

Paket ini tidak menyertakan Loop Agent dan Discovery.

## Status, backup, dan update

```sh
sh deploy.sh status
sh deploy.sh doctor
docker compose --env-file .env.local logs --tail 100 app
```

Backup harus memasangkan database, volume runtime/master key, dan `.env.local`. Buat direktori backup dengan akses terbatas terlebih dahulu, lalu saat tidak ada job aktif:

```sh
sh deploy.sh backup /lokasi/backup
```

Perintah menghentikan app sementara dan menyalakannya kembali setelah backup. Backup mengandung data rahasia; simpan terenkripsi di luar repository dan di luar VPS. Restore memerlukan database dan runtime/master key dari pasangan yang sama.

Untuk update: tunggu jobs selesai, backup, unduh aset versi baru, verifikasi checksum, muat image, perbarui file deployment dengan mempertahankan `.env.local`, lalu jalankan `sh deploy.sh up`. Bila versi lama memakai Caddy, jalankan dulu `docker compose --env-file .env.local --profile https stop caddy` sebelum memperbarui file. Migrasi database berjalan saat app mulai; tidak ada rollback database otomatis. Jangan menjalankan `docker compose down -v` selama data masih diperlukan.

Saat update dari versi yang masih memiliki `loop-worker`, hentikan dulu sesudah backup dan sebelum `sh deploy.sh up`:

```sh
docker compose --env-file .env.local --profile loop-agent stop loop-worker
```

Binary Rust tetap dapat dianalisis; distribusi binary tidak menjamin perlindungan mutlak terhadap rekayasa balik. Source Rust tetap dikelola pada repository pengembangan internal.

## Perubahan versi 0.1.2

- Cron memiliki jenis baru **Scraping laporan lalu POST ke API**: formulir laporan harian untuk tanggal jadwal, dan pada tanggal 1 juga formulir bulanan bulan yang baru selesai. Jadwal yang sudah ada tidak berubah.
- Jadwal yang mengirim mengambil ulang otomatis, dalam job terpisah, tanggal 7 hari terakhir yang run-nya gagal atau terlewati, dan tanggal kunjungan yang masih memiliki record tidak lengkap.
- Caddy tidak lagi disertakan. HTTPS disediakan reverse proxy Anda, misalnya nginx dengan certbot, dan `SCRAPER_DOMAIN` tidak lagi dipakai.
- Versi ini menambah migrasi database (`0024`): kembali ke versi lama memerlukan restore database dari backup.

Release ini menyediakan image Linux/amd64 `puskesmas-scraper:0.1.2` dan alias `puskesmas-scraper:rust-hybrid`. Compose memakai tag versi tetap. Saat upgrade, perbarui juga Compose dan README dari paket deployment; jangan hanya memuat image baru dengan Compose lama. Pertahankan `.env.local`, database, volume runtime, dan master key.

## Perubahan versi 0.2.26

- Scraping per kunjungan dan semua laporan, termasuk Laporan Pelayanan KIA, kini dibaca oleh binary Rust. Python hanya menjalankan login Scrapling.
- Loop Agent dan Discovery tidak disertakan; menu dan URL-nya menjawab 404. Service `loop-worker` tidak lagi berjalan.
- Varian portal melalui `endpoint_variants`/`schema_variants` di `simpus_rules.json` belum didukung; job dengan varian seperti itu gagal dengan pesan yang jelas.
- ID Puskesmas pada API Ingest (`X-Puskesmas-Id`) kini berasal dari akun SIMPUS, sehingga pengguna berbeda dengan login yang sama memperoleh ID yang sama. Kode Puskesmas dikirim sebagai `puskesmas_code`, dan nama sebagai `puskesmas_name`.
- ID pasien pada API Ingest kini sama untuk NIK yang sama di semua pengguna. Nilai `patient_key` yang sudah pernah dikirim berubah, sehingga penerima perlu memetakan ulang.
- Kunjungan yang terbaca tidak lengkap tidak dikirim dan tidak menimpa data lengkap; job selesai dengan penanda `incomplete_records`, dan alasannya tercatat di log job.
- Versi ini menambah migrasi database (`0023`): kembali ke versi lama memerlukan restore database dari backup.

## Perubahan versi 0.2.0

- Pengambilan pasien mencakup data medis di luar CKG, mengikuti layanan dan data yang tersedia pada portal sumber.
- Export per pasien, JSON dengan nama field yang jelas, serta FHIR R4 JSON/NDJSON. Identifier dan referensi FHIR memakai UUID stabil dengan pemisahan per akun, Puskesmas, dan sumber. Data sumber dan kesenjangan pemetaan tetap dapat ditelusuri; export parsial tidak menyatakan semua persyaratan profil nasional sudah terpenuhi.
- Scrape ulang memperbarui record kunjungan pasien yang sama pada tanggal yang sama. Kunjungan, tanggal, atau akun berbeda tetap dipisahkan.
- Timeout scraping 90 menit per tanggal kunjungan. Rentang tanggal memakai timer baru tiap tanggal; timeout mempertahankan data tersimpan lalu melanjutkan tanggal berikutnya. Job tetap gagal bila ada tanggal gagal; rincian tercatat di log. Cancel menghentikan sisa rentang.
- Admin dapat membuka **Pengaturan scraper** (`/scraper-settings`) untuk default worker pasien dan tab per pasien. Default 5 x 3; masing-masing 1–8 dengan perkalian maksimal 32. Berlaku untuk job baru tanpa restart. Mulai dengan 2 x 2 pada perangkat terbatas dan sesuaikan berdasarkan pengamatan CPU/RAM serta respons portal.
- Deployment mendukung `SYSTEM_MAX_CONCURRENT_JOBS` (1–4, default 1) dan `APP_MEMORY_LIMIT` (default `2g`). Perubahan parameter deployment memerlukan pembuatan ulang container ketika job tidak aktif.
- Controller container memakai capability `KILL` agar dapat menghentikan worker Linux UID 10002 pada cancel/timeout. UID worker adalah akun proses, terpisah dari identifier pasien.
- Halaman record menyediakan JSON berindentasi, warna sintaks, buka/lipat struktur, tampilan teks, dan salin JSON tanpa mengubah angka atau identifier.
