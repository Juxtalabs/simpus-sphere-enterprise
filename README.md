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
