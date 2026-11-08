# GSP768 - Understanding and Combining GKE Autoscaling Strategies

Script bantu otomatis untuk lab **GSP768** (Google Cloud Skills Boost).
Script mengerjakan seluruh task lab lewat Cloud Shell dan berhenti di setiap tombol **Check my progress**, jadi kamu bisa mengecek progres dulu sebelum lanjut.

**Credit: Jutapen** - https://github.com/Jutapen

## Cara pakai

1. Mulai lab, lalu buka Google Cloud console dengan akun student dari panel **Lab setup and access** (disarankan di jendela Incognito).
2. Aktifkan **Cloud Shell**.
3. Jalankan satu baris ini:

```bash
curl -fsSL https://raw.githubusercontent.com/Jutapen/GSP768/main/gsp768.sh | bash
```

Project ID dan zone diambil otomatis dari konfigurasi `gcloud`. Kalau zone belum diatur, script akan menanyakannya (lab ini memakai `us-west1-b`).

Atau unduh dulu lalu jalankan:

```bash
curl -fsSL -o gsp768.sh https://raw.githubusercontent.com/Jutapen/GSP768/main/gsp768.sh
bash gsp768.sh
```

## Langkah manual (GUI)

Beberapa hal tetap kamu lakukan di browser:

1. **Klik "Check my progress"** di halaman lab setiap kali script berhenti, lalu tekan ENTER di Cloud Shell. Ada 6 titik cek:
   - Provision testing environment
   - Scale pods with Horizontal Pod Autoscaling
   - Scale size of pods with Vertical Pod Autoscaling
   - Cluster autoscaler
   - Node Auto Provisioning
   - Optimize larger loads
2. (Opsional) Amati hasilnya di console: **Kubernetes Engine > Clusters > scaling-demo > Nodes**, lalu refresh untuk melihat node bertambah atau berkurang.
3. Task 7 (uji beban) tidak punya tombol cek.

## Yang normal terjadi

- Pembuatan cluster butuh sekitar 3-5 menit, dan setiap `gcloud ... update` butuh beberapa menit.
- Script menunggu dengan sabar: rekomendasi VPA (sampai ~5 menit), HPA turun ke 1 replika (sampai ~10 menit), dan cluster turun ke 2 node (sampai ~10 menit). Jangan di-Ctrl+C.
- Kalau pod `hello-server` masih memakai CPU request 450m, script menyetelnya manual ke 25m, sesuai catatan di lab.
- Node Auto Provisioning kemungkinan besar belum membuat node pool baru saat Task 6.
- Saat uji beban, `php-apache` naik sampai sekitar 7 replika dan node bertambah, mungkin dengan node pool baru dari NAP. Setelah load generator dihentikan, cluster pelan-pelan turun lagi.
- Di Task 8, satu node baru muncul untuk menampung pause pod, biasanya di node pool baru.
- Pesan "sudah ada, dilewati" atau "kemungkinan sudah aktif" muncul kalau script dijalankan ulang. Itu normal karena script idempotent.
- Kalau skor belum naik setelah klik Check my progress, tunggu 1-2 menit lalu klik lagi.

## Disclaimer

Repo ini hanya untuk tujuan edukasi dan **tidak berafiliasi dengan Google**. Gunakan hanya dengan **akun student lab** yang diberikan oleh lab, jangan dengan akun Google Cloud pribadi, agar tidak ada biaya atau konflik di akun kamu. Gunakan dengan tanggung jawab sendiri.

## Lisensi

[MIT](LICENSE) - Copyright (c) 2026 Jutapen
