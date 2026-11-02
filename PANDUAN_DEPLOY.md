# Panduan Deployment Puskesmas Scraper 0.1.2

Panduan ini untuk **maintainer server**, yaitu orang yang punya akses `sudo` ke server. Ikuti langkahnya berurutan dan periksa hasilnya sebelum lanjut. Bila hasilnya berbeda, berhenti dan lihat bagian "Jika ada masalah".

Di semua perintah, ganti `USER@IP_SERVER` dengan akun dan alamat server Anda, dan `scraper.domainanda.com` dengan domain Anda.

## Yang perlu disiapkan

| Kebutuhan | Minimum |
|---|---|
| Sistem operasi | Linux/amd64, disarankan Ubuntu LTS |
| CPU / RAM | 2 vCPU / 4 GB |
| Disk | 40 GB, dengan minimal 10 GB kosong saat instalasi |
| Software | Docker Engine dan Docker Compose v2 |
| Koneksi keluar (HTTPS) | `github.com`, `release-assets.githubusercontent.com`, `auth.docker.io`, `registry-1.docker.io`, portal SIMPUS, API tujuan |
| Koneksi masuk | Port 22, 80, 443 |
| Domain | Domain atau subdomain dengan DNS A menuju IP server |

Siapkan juga login SIMPUS yang berwenang, serta URL dan kredensial API tujuan bila hasil akan dikirim.

## Instalasi

### 1. Masuk ke server

Dari PowerShell atau terminal komputer Anda:

```sh
ssh USER@IP_SERVER
```

Semua langkah berikutnya dijalankan **di server**, bukan di komputer Anda.

### 2. Cek prasyarat

```sh
sudo docker version
sudo docker compose version
command -v curl openssl unzip sha256sum
```

**Hasil yang benar:** Docker dan Compose menampilkan versinya, dan keempat alat menampilkan lokasinya.

Bila Docker belum ada, pasang dengan [panduan resmi Docker](https://docs.docker.com/engine/install/), lalu ulangi langkah ini.

### 3. Unduh dari GitHub

Ukuran unduhan sekitar 600 MB.

```sh
mkdir -p ~/puskesmas-0.1.2 && cd ~/puskesmas-0.1.2
base=https://github.com/Juxtalabs/simpus-sphere-enterprise/releases/download/v0.1.2
curl -fLO "$base/puskesmas-scraper-rust-hybrid.tar.gz"
curl -fLO "$base/puskesmas-scraper-deployment.zip"
curl -fLO "$base/release-manifest.json"
curl -fLO "$base/SHA256SUMS"
sha256sum --check SHA256SUMS
```

**Hasil yang benar:** ketiga file menampilkan `OK`. Bila tidak, hapus file lalu unduh ulang. Jangan lanjut.

### 4. Pasang paket

```sh
sudo docker image load --input puskesmas-scraper-rust-hybrid.tar.gz
sudo install -d -o "$USER" -g "$(id -gn)" /opt/puskesmas-scraper
unzip puskesmas-scraper-deployment.zip -d /opt
cd /opt/puskesmas-scraper
sh deploy.sh prepare
```

**Hasil yang benar:** baris terakhir `Settings prepared.`

Semua perintah berikutnya dijalankan dari `/opt/puskesmas-scraper`.

### 5. Atur konfigurasi

```sh
nano .env.local
```

Biarkan baris `POSTGRES_PASSWORD` apa adanya. Sesuaikan sisanya seperti ini, dan tambahkan dua baris terakhir karena belum ada:

```dotenv
WEB_PORT=3003
ALLOW_PRIVATE_DESTINATIONS=false
COOKIE_SECURE=true
SYSTEM_MAX_CONCURRENT_JOBS=1
APP_MEMORY_LIMIT=2g
```

Simpan dengan `Ctrl+O`, lalu `Enter`, dan keluar dengan `Ctrl+X`.

### 6. Cek port yang terpakai

```sh
sudo ss -ltnp | grep -E ':(80|443|3003|5435)\b'
```

| Port yang muncul | Tindakan |
|---|---|
| 5435 | Wajib buat override di bawah ini. Tanpa itu database gagal start. |
| 3003 | Ganti `WEB_PORT` di `.env.local` ke port kosong, dan pakai port yang sama di langkah 9. |
| 80 atau 443 | Wajar bila nginx sudah terpasang. Bila yang memakai reverse proxy lain, arahkan domain ke aplikasi dari proxy itu dan lewati langkah 9. |

Override untuk port 5435 juga aman dipakai bila port itu kosong, karena aplikasi mengakses database lewat jaringan internal:

```sh
cat > compose.override.yaml <<'EOF'
services:
  postgres:
    ports: !reset []
EOF
```

Langkah ini hanya memeriksa port dan membuat satu file, sehingga tidak mengganggu aplikasi lain di server.

### 7. Buat akun administrator

```sh
sudo sh deploy.sh init
```

Isi username dan password minimal 12 karakter. Password tidak tampil saat diketik. Tidak ada akun bawaan.

**Hasil yang benar:** baris terakhir `Start the server with: puskesmas-scraper serve`. Perintah itu tidak perlu dijalankan, karena langkah berikutnya sudah menyalakan aplikasi.

Langkah ini juga membuat master key untuk mengenkripsi data, sehingga master key wajib ikut di-backup.

### 8. Jalankan aplikasi

```sh
sudo sh deploy.sh up
```

**Hasil yang benar:** `app` dan `postgres` menampilkan `Healthy`.

### 9. Hubungkan domain dengan HTTPS

Lewati langkah ini bila nginx untuk domain Anda sudah mengarah ke port aplikasi.

Pastikan DNS domain sudah mengarah ke server. Bila nginx dan certbot belum ada, pasang dengan pengelola paket server Anda. Di Ubuntu:

```sh
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

Buat file konfigurasi nginx:

- Ubuntu: `/etc/nginx/sites-available/puskesmas-scraper`
- AlmaLinux, Rocky, atau RHEL: `/etc/nginx/conf.d/puskesmas-scraper.conf`

```nginx
server {
    listen 80;
    server_name scraper.domainanda.com;
    client_max_body_size 100m;

    location / {
        proxy_pass http://127.0.0.1:3003;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
}
```

Khusus Ubuntu, aktifkan dulu konfigurasinya:

```sh
sudo ln -s /etc/nginx/sites-available/puskesmas-scraper /etc/nginx/sites-enabled/puskesmas-scraper
```

Lalu periksa, muat ulang, dan pasang sertifikat:

```sh
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d scraper.domainanda.com
```

Bila server menjalankan situs lain, `nginx -t` harus berhasil sebelum reload. HTTPS wajib selama `COOKIE_SECURE=true`. Lewat HTTP biasa, login tidak akan bertahan.

### 10. Cek instalasi

```sh
sudo sh deploy.sh status
sudo sh deploy.sh doctor
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3003/healthz
curl -s -o /dev/null -w "%{http_code}\n" https://scraper.domainanda.com/healthz
```

**Hasil yang benar:**

- `status` menampilkan kedua service `healthy`.
- `doctor` diakhiri `OK: no blocking problems found.`
- Kedua `curl` menjawab `200`.

Lalu buka `https://scraper.domainanda.com` dan login.

### 11. Uji aplikasi

1. **Puskesmas:** tambahkan nama dan URL SIMPUS, lalu simpan login SIMPUS. Kode Puskesmas boleh dikosongkan sampai kode resminya ditetapkan.
2. **Scraping pertama:** jalankan satu tanggal yang punya banyak kunjungan, bukan hari libur.
3. **Periksa hasil:** job harus selesai, jumlah kunjungan sama dengan portal, dan log job tidak memuat `kunjungan tidak lengkap`.
4. **Laporan:** jalankan satu tanggal lalu bandingkan jumlah barisnya dengan portal, terutama `pelayanan_pasien`. `kohort_kia` adalah laporan bulanan, jadi periksa dengan satu bulan.
5. **Kirim ke API:** lakukan setelah disepakati dengan pihak penerima. Untuk SPHERES, biarkan **Mode uji** aktif dan beri tahu mereka `X-Puskesmas-Id`, karena setiap instalasi baru menghasilkan ID berbeda.
6. **Cron:** buat jadwal setelah langkah di atas berhasil.

| Jenis jadwal | Fungsi |
|---|---|
| Scraping saja | Mengambil kunjungan tanpa mengirim |
| Scraping lalu POST ke API | Mengambil kunjungan lalu mengirim |
| Scraping laporan lalu POST ke API | Mengambil laporan harian lalu mengirim; pada tanggal 1 juga laporan bulanan bulan lalu |
| POST hasil tersimpan | Mengirim hasil yang sudah ada |

Beri jarak antarjadwal pada Puskesmas yang sama, misalnya kunjungan 17:30 dan laporan 19:30. Jadwal yang jatuh saat job lain masih berjalan akan dilewati. Dua jenis jadwal yang mengirim mengambil ulang sendiri tanggal yang gagal atau terlewati dalam 7 hari terakhir.

## Checklist kelancaran

Centang berurutan. Bila ada yang gagal, berhenti di situ dan lihat bagian "Jika ada masalah".

### Instalasi

- [ ] Hasil langkah 10 semuanya benar.
- [ ] Gembok HTTPS tampil valid di browser.
- [ ] Login administrator berhasil dan tetap masuk saat berpindah halaman.

### Scraping

- [ ] Job satu tanggal yang punya kunjungan berstatus selesai.
- [ ] Jumlah kunjungan pada job sama dengan portal SIMPUS.
- [ ] Log job tidak memuat `kunjungan tidak lengkap`.
- [ ] Job laporan selesai, dan jumlah barisnya sama dengan portal.

### Pengiriman

- [ ] Mode uji aktif pada tujuan SPHERES, dan uji koneksi menyatakan koneksi siap.
- [ ] Sync satu tanggal selesai tanpa kiriman gagal, dan pihak penerima mengonfirmasi datanya masuk.

### Pemakaian rutin

- [ ] Jadwal Cron berjalan sendiri pada waktunya dan job-nya selesai. Periksa keesokan harinya.
- [ ] Selama job besar berjalan, `sudo docker stats --no-stream` menunjukkan memori `app` di bawah `APP_MEMORY_LIMIT`.
- [ ] `df -h /` menyisakan ruang minimal sebesar satu backup.
- [ ] Backup berhasil, dan aplikasi kembali `healthy` sesudahnya.
- [ ] Setelah `sudo reboot`, aplikasi menyala sendiri dan login masih berfungsi.

Untuk mencari kesalahan di log:

```sh
sudo docker compose --env-file .env.local logs --tail 500 app | grep -iE "error|panic"
```

Periksa isi baris yang keluar sebelum membagikannya.

## Backup

Jalankan saat tidak ada job aktif. **Aplikasi berhenti selama proses ini**, dan lamanya tergantung ukuran data.

```sh
sudo install -d -m 700 /srv/puskesmas-backup
sudo sh deploy.sh backup /srv/puskesmas-backup
```

Setiap backup adalah folder `simpus-<waktu>` berisi tiga file yang harus tetap sepasang:

| File | Isi |
|---|---|
| `database.dump` | Database |
| `runtime.tar.gz` | Data runtime dan master key |
| `config.env` | Salinan `.env.local` |

Tanpa master key yang sepasang, data terenkripsi tidak bisa dibaca. Simpan salinan backup terenkripsi di luar server, dan perlakukan foldernya seperti password. Satu backup kira-kira sebesar databasenya.

## Restore

Langkah ini **menghapus seluruh data saat ini**, lalu menggantinya dengan isi backup. Lakukan hanya bila memang perlu.

```sh
sudo -s
cd /opt/puskesmas-scraper
B=/srv/puskesmas-backup/simpus-WAKTU_BACKUP

docker compose --env-file .env.local down -v

cp "$B/config.env" .env.local
chmod 600 .env.local

docker compose --env-file .env.local up -d --wait postgres
docker compose --env-file .env.local exec -T postgres pg_restore -U puskesmas -d puskesmas_rust --no-owner --exit-on-error < "$B/database.dump"
docker compose --env-file .env.local up --no-start app
docker run --rm --mount type=volume,src=puskesmas-scraper-rust_runtime_data,dst=/data --mount "type=bind,src=$B,dst=/backup,readonly" --entrypoint tar puskesmas-scraper:rust-hybrid xzf /backup/runtime.tar.gz -C /data
exit
```

Bila memulihkan ke server baru, jalankan dulu langkah 1 sampai 4 tanpa `sh deploy.sh prepare`, buat ulang override bila perlu, lalu lewati baris `down -v`.

Sesudahnya jalankan langkah 8, lalu periksa seperti langkah 10.

## Update ke versi baru

Tunggu semua job selesai, lalu buat backup. Unduh versi baru seperti langkah 3 dengan nomor versi yang baru, lalu dari folder unduhan:

```sh
sudo docker image load --input puskesmas-scraper-rust-hybrid.tar.gz
unzip -o puskesmas-scraper-deployment.zip -d /opt
cd /opt/puskesmas-scraper
sudo sh deploy.sh up
```

`.env.local` dan `compose.override.yaml` tidak ikut tertimpa, dan migrasi database berjalan otomatis. Periksa seperti langkah 10.

**Kembali ke versi lama:** jangan hanya mengganti image, karena database sudah dimigrasi. Pasang image dan file versi lama, lalu lakukan restore dari backup yang dibuat sebelum update.

## Perintah sehari-hari

| Keperluan | Perintah |
|---|---|
| Status | `sudo sh deploy.sh status` |
| Pemeriksaan | `sudo sh deploy.sh doctor` |
| Log (Ctrl+C untuk keluar) | `sudo sh deploy.sh logs` |
| Hentikan, data tetap ada | `sudo sh deploy.sh down` |
| Jalankan kembali | `sudo sh deploy.sh up` |
| Reset password admin | `sudo sh deploy.sh init`, lalu isi username yang sama |

## Jika ada masalah

| Gejala | Yang harus dilakukan |
|---|---|
| `sudo` atau `apt-get` tidak ditemukan di Windows | Anda masih di PowerShell. Masuk dulu ke server (langkah 1). |
| `curl` gagal saat mengunduh | Periksa koneksi keluar ke alamat di bagian "Yang perlu disiapkan". |
| Checksum tidak `OK` | Hapus file lalu unduh ulang. Jangan lanjut. |
| `port is already allocated` untuk 5435 | Buat `compose.override.yaml` (langkah 6), lalu jalankan ulang. |
| `port is already allocated` untuk 3003 | Ganti `WEB_PORT` di `.env.local` (langkah 6), lalu jalankan ulang. |
| `master key not found`, atau `app` terus restart | `init` belum dijalankan. Jalankan langkah 7. |
| `run prepare first` | `.env.local` tidak ada. Pastikan Anda di `/opt/puskesmas-scraper`, lalu jalankan `sh deploy.sh prepare`. |
| Login berhasil tetapi kembali ke halaman login | Membuka lewat HTTP biasa. Pakai HTTPS. |
| 502 dari nginx | Aplikasi belum menyala, atau `WEB_PORT` berbeda dari `proxy_pass`. Cek `sudo sh deploy.sh status`. |
| Sertifikat HTTPS gagal terbit | DNS belum mengarah ke server, atau port 80/443 tertutup. |
| Job gagal dengan pesan varian portal | Versi ini belum mendukung `endpoint_variants`/`schema_variants`. Hubungi tim JuxtaLabs. |
| Job gagal saat login | Periksa login SIMPUS dan koneksi server ke portal. Jangan mengulang terus-menerus agar akun tidak terkunci. |

Saat meminta bantuan, kirim hasil `sudo sh deploy.sh status` dan `sudo sh deploy.sh doctor`.

### Jangan pernah

- Menjalankan `docker compose down -v` di luar prosedur restore. Perintah ini menghapus database dan master key.
- Menjalankan `docker prune` apa pun bila server dipakai bersama aplikasi lain.
- Membuka port database atau aplikasi (5435, 3003) langsung ke internet.
- Memisahkan `database.dump`, `runtime.tar.gz`, dan `config.env` dari satu backup.
- Mengirim `.env.local`, master key, file backup, password, atau data pasien lewat tiket, chat, atau screenshot.
