#!/bin/bash
# ==============================================================================
#  GSP768 - Understanding and Combining GKE Autoscaling Strategies
#  Credit : Jutapen
#  GitHub : https://github.com/Jutapen
#
#  Script bantu untuk lab Google Cloud Skills Boost (GSP768).
#  Jalankan di Cloud Shell dengan akun student lab. Hanya untuk edukasi.
#  Script berhenti di setiap "Check my progress" supaya kamu bisa klik cek
#  progres dulu sebelum lanjut. Aman dijalankan ulang (idempotent).
# ==============================================================================

set -eE

# ---------- warna (nonaktif kalau output bukan terminal) ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  USE_COLOR=1
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_CYN=$'\033[36m'
else
  USE_COLOR=0
  C_RESET=""; C_BOLD=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_CYN=""
fi

info()  { printf '%s[INFO]%s  %s\n'  "$C_BLU" "$C_RESET" "$*"; }
ok()    { printf '%s[ OK ]%s  %s\n'  "$C_GRN" "$C_RESET" "$*"; }
warn()  { printf '%s[WARN]%s  %s\n'  "$C_YEL" "$C_RESET" "$*"; }
error() { printf '%s[ERROR]%s %s\n'  "$C_RED" "$C_RESET" "$*" >&2; }

# ---------- jeda di setiap Check my progress ----------
pause_check() {
  echo
  printf '%s==================================================%s\n' "$C_CYN" "$C_RESET"
  printf '%s>>> KLIK "Check my progress" untuk: %s%s\n' "$C_BOLD" "$1" "$C_RESET"
  printf '%s==================================================%s\n' "$C_CYN" "$C_RESET"
  read -rp "Tekan ENTER setelah progres dicek ... " _ </dev/tty || true
  echo
}

# ---------- efek ketik (nonaktif kalau bukan terminal) ----------
typeout() {
  local s="$1" i
  if [ "$USE_COLOR" = 1 ]; then
    for ((i = 0; i < ${#s}; i++)); do
      printf '%s' "${s:i:1}"
      sleep 0.03
    done
    printf '\n'
  else
    printf '%s\n' "$s"
  fi
}

# ---------- banner DONE (gradasi 256-color) ----------
banner_done() {
  local colors=(51 45 39 33 27)
  local lines=(
' ____   ___  _   _ _____'
'|  _ \ / _ \| \ | | ____|'
'| | | | | | |  \| |  _|'
'| |_| | |_| | |\  | |___'
'|____/ \___/|_| \_|_____|'
  )
  local i
  for i in "${!lines[@]}"; do
    if [ "$USE_COLOR" = 1 ]; then
      printf '\033[38;5;%sm%s\033[0m\n' "${colors[$i]}" "${lines[$i]}"
    else
      printf '%s\n' "${lines[$i]}"
    fi
  done
}

# ---------- helper PDB (lewati kalau sudah ada) ----------
create_pdb() {
  local name="$1" selector="$2"
  if kubectl get pdb "$name" -n kube-system >/dev/null 2>&1; then
    info "PDB $name sudah ada, dilewati."
  else
    kubectl create poddisruptionbudget "$name" --namespace=kube-system --selector "$selector" --max-unavailable 1
  fi
}

# Seluruh logika dibungkus fungsi main supaya aman dijalankan lewat `curl | bash`
# (bash membaca seluruh script dulu, stdin tidak "dimakan" oleh gcloud/kubectl).
main() {
  trap 'error "Gagal di baris $LINENO. Perbaiki penyebabnya lalu jalankan ulang script (aman, idempotent)."' ERR

  printf '%s' "$C_BOLD"
  echo "=================================================="
  echo " GSP768 - Understanding and Combining GKE Autoscaling"
  echo " Credit: Jutapen"
  echo "=================================================="
  printf '%s' "$C_RESET"

  # ---------- nilai otomatis dari gcloud / environment ----------
  PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
  if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    error "Project belum terdeteksi. Buka Cloud Shell dari tab student lab, lalu coba lagi."
    exit 1
  fi
  info "Project aktif: $PROJECT_ID"

  ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || true)}"
  if [ -z "$ZONE" ] || [ "$ZONE" = "(unset)" ]; then
    read -rp "Zone belum diatur. Masukkan zone sesuai lab (contoh: us-west1-b): " ZONE </dev/tty
  fi
  if [ -z "$ZONE" ]; then
    error "Zone kosong."
    exit 1
  fi
  if [ "$ZONE" != "us-west1-b" ]; then
    warn "Lab menginstruksikan zone us-west1-b, sedangkan yang dipakai: $ZONE"
  fi
  info "Zone: $ZONE"

  WORKDIR="$HOME/gsp768-work"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"

  ############################################
  # Provision testing environment
  ############################################
  info "Provision testing environment"
  gcloud config set compute/zone "$ZONE"

  if gcloud container clusters describe scaling-demo --zone "$ZONE" >/dev/null 2>&1; then
    info "Cluster scaling-demo sudah ada, dilewati."
  else
    gcloud container clusters create scaling-demo --num-nodes=3 --enable-vertical-pod-autoscaling
  fi
  gcloud container clusters get-credentials scaling-demo --zone "$ZONE"

  cat << EOF > php-apache.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  selector:
    matchLabels:
      run: php-apache
  replicas: 3
  template:
    metadata:
      labels:
        run: php-apache
    spec:
      containers:
      - name: php-apache
        image: k8s.gcr.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
  labels:
    run: php-apache
spec:
  ports:
  - port: 80
  selector:
    run: php-apache
EOF

  kubectl apply -f php-apache.yaml
  kubectl rollout status deployment/php-apache --timeout=300s || true
  kubectl get deployment
  ok "Environment siap."

  pause_check "Provision testing environment"

  ############################################
  # Task 1. Horizontal Pod Autoscaling
  ############################################
  info "Task 1. Horizontal Pod Autoscaling"
  if kubectl get hpa php-apache >/dev/null 2>&1; then
    info "HPA php-apache sudah ada, dilewati."
  else
    kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10
  fi
  kubectl get hpa
  ok "HPA aktif."

  pause_check "Scale pods with Horizontal Pod Autoscaling"

  ############################################
  # Task 2. Vertical Pod Autoscaling
  ############################################
  info "Task 2. Vertical Pod Autoscaling"
  gcloud container clusters describe scaling-demo --zone "$ZONE" | grep ^verticalPodAutoscaling -A 1 || true

  if kubectl get deployment hello-server >/dev/null 2>&1; then
    info "Deployment hello-server sudah ada, dilewati."
  else
    kubectl create deployment hello-server --image=gcr.io/google-samples/hello-app:1.0
  fi
  kubectl rollout status deployment/hello-server --timeout=300s || true
  kubectl get deployment hello-server

  kubectl set resources deployment hello-server --requests=cpu=450m
  kubectl rollout status deployment/hello-server --timeout=300s || true
  kubectl describe pod hello-server | sed -n "/Containers:$/,/Conditions:/p"

  cat << EOF > hello-vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hello-server-vpa
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind:       Deployment
    name:       hello-server
  updatePolicy:
    updateMode: "Off"
EOF

  kubectl apply -f hello-vpa.yaml

  info "Menunggu Container Recommendations muncul (maks ~5 menit)..."
  for _ in $(seq 1 30); do
    if kubectl describe vpa hello-server-vpa | grep -q "Container Recommendations"; then
      break
    fi
    sleep 10
  done
  kubectl describe vpa hello-server-vpa

  sed -i 's/Off/Auto/g' hello-vpa.yaml
  kubectl apply -f hello-vpa.yaml

  kubectl scale deployment hello-server --replicas=2

  info "Menunggu VPA me-resize pod hello-server (maks ~4 menit)..."
  for _ in $(seq 1 24); do
    REQS=$(kubectl get pods -l app=hello-server -o jsonpath='{range .items[*]}{.spec.containers[0].resources.requests.cpu}{"\n"}{end}' 2>/dev/null || true)
    if [ -n "$REQS" ] && echo "$REQS" | grep -qv '^450m$'; then
      break
    fi
    sleep 10
  done
  kubectl get pods
  ok "VPA mode Auto aktif."

  pause_check "Scale size of pods with Vertical Pod Autoscaling"

  ############################################
  # Task 3. HPA results
  ############################################
  info "Task 3. Hasil HPA"
  info "Menunggu php-apache turun ke 1 replika (maks ~10 menit)..."
  for _ in $(seq 1 60); do
    REP=$(kubectl get deployment php-apache -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)
    if [ "${REP:-0}" = "1" ]; then
      break
    fi
    sleep 10
  done
  kubectl get hpa

  ############################################
  # Task 4. VPA results
  ############################################
  info "Task 4. Hasil VPA"
  kubectl describe pod hello-server | sed -n "/Containers:$/,/Conditions:/p"

  STILL=$(kubectl get pods -l app=hello-server -o jsonpath='{range .items[*]}{.spec.containers[0].resources.requests.cpu}{"\n"}{end}' | grep -c '^450m$' || true)
  if [ "${STILL:-0}" -gt 0 ]; then
    warn "Masih ada pod dengan CPU request 450m, set manual ke 25m sesuai catatan lab."
    kubectl set resources deployment hello-server --requests=cpu=25m
    kubectl rollout status deployment/hello-server --timeout=300s || true
    kubectl describe pod hello-server | sed -n "/Containers:$/,/Conditions:/p"
  fi

  ############################################
  # Task 5. Cluster autoscaler
  ############################################
  info "Task 5. Cluster autoscaler"
  gcloud beta container clusters update scaling-demo --enable-autoscaling --min-nodes 1 --max-nodes 5 --zone "$ZONE" \
    || warn "Autoscaling kemungkinan sudah aktif, lanjut."

  gcloud beta container clusters update scaling-demo --autoscaling-profile optimize-utilization --zone "$ZONE" \
    || warn "Profile kemungkinan sudah optimize-utilization, lanjut."

  kubectl get deployment -n kube-system

  create_pdb kube-dns-pdb k8s-app=kube-dns
  create_pdb prometheus-pdb k8s-app=prometheus-to-sd
  create_pdb kube-proxy-pdb component=kube-proxy
  create_pdb metrics-agent-pdb k8s-app=gke-metrics-agent
  create_pdb metrics-server-pdb k8s-app=metrics-server
  create_pdb fluentd-pdb k8s-app=fluentd-gke
  create_pdb backend-pdb k8s-app=glbc
  create_pdb kube-dns-autoscaler-pdb k8s-app=kube-dns-autoscaler
  create_pdb stackdriver-pdb app=stackdriver-metadata-agent
  create_pdb event-pdb k8s-app=event-exporter

  info "Menunggu cluster turun ke 2 node (maks ~10 menit)..."
  for _ in $(seq 1 60); do
    N=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$N" -le 2 ]; then
      break
    fi
    sleep 10
  done
  kubectl get nodes

  pause_check "Cluster autoscaler"

  ############################################
  # Task 6. Node Auto Provisioning
  ############################################
  info "Task 6. Node Auto Provisioning"
  gcloud container clusters update scaling-demo \
      --enable-autoprovisioning \
      --min-cpu 1 \
      --min-memory 2 \
      --max-cpu 45 \
      --max-memory 160 \
      --zone "$ZONE" \
    || warn "NAP kemungkinan sudah aktif, lanjut."

  pause_check "Node Auto Provisioning"

  ############################################
  # Task 7. Test with larger demand
  ############################################
  info "Task 7. Test dengan beban lebih besar"
  kubectl delete pod load-generator --ignore-not-found=true
  kubectl run load-generator --image=busybox --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"

  info "Menunggu php-apache scale up ke 7 replika (maks ~20 menit)..."
  for i in $(seq 1 120); do
    READY=$(kubectl get deployment php-apache -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    echo "[$i] HPA:"
    kubectl get hpa --no-headers || true
    echo "     php-apache ready: ${READY:-0}"
    if [ "${READY:-0}" -ge 7 ]; then
      break
    fi
    sleep 10
  done
  kubectl get deployment php-apache
  kubectl get nodes

  info "Menghentikan load generator (setara Ctrl+C)..."
  kubectl delete pod load-generator --ignore-not-found=true

  ############################################
  # Task 8. Optimize larger loads
  ############################################
  info "Task 8. Overprovision dengan Pause Pods"
  cat << EOF > pause-pod.yaml
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: overprovisioning
value: -1
globalDefault: false
description: "Priority class used by overprovisioning."
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: overprovisioning
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      run: overprovisioning
  template:
    metadata:
      labels:
        run: overprovisioning
    spec:
      priorityClassName: overprovisioning
      containers:
      - name: reserve-resources
        image: k8s.gcr.io/pause
        resources:
          requests:
            cpu: 1
            memory: 4Gi
EOF

  kubectl apply -f pause-pod.yaml

  info "Menunggu pause pod terjadwal (maks ~10 menit)..."
  kubectl rollout status deployment/overprovisioning -n kube-system --timeout=600s || true
  kubectl get nodes
  kubectl get pods -n kube-system | grep overprovisioning || true

  pause_check "Optimize larger loads"

  ############################################
  # Ringkasan hasil
  ############################################
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  POOLS=$(gcloud container node-pools list --cluster scaling-demo --zone "$ZONE" --format='value(name)' 2>/dev/null | tr '\n' ' ' || true)
  PHP_REP=$(kubectl get deployment php-apache -o jsonpath='{.status.replicas}' 2>/dev/null || echo "-")
  HELLO_CPU=$(kubectl get pods -l app=hello-server -o jsonpath='{.items[0].spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "-")

  echo
  banner_done
  echo
  printf '%sGSP768 - Understanding and Combining GKE Autoscaling Strategies%s\n' "$C_BOLD" "$C_RESET"
  echo
  printf '%s  ✔%s Cluster scaling-demo dibuat (3 node, VPA aktif)\n'               "$C_GRN" "$C_RESET"
  printf '%s  ✔%s Horizontal Pod Autoscaler php-apache (min 1, max 10, CPU 50%%)\n'  "$C_GRN" "$C_RESET"
  printf '%s  ✔%s Vertical Pod Autoscaler hello-server (mode Auto)\n'               "$C_GRN" "$C_RESET"
  printf '%s  ✔%s Cluster Autoscaler (1-5 node, profil optimize-utilization) + PDB kube-system\n' "$C_GRN" "$C_RESET"
  printf '%s  ✔%s Node Auto Provisioning aktif\n'                                   "$C_GRN" "$C_RESET"
  printf '%s  ✔%s Uji beban dengan load-generator\n'                                "$C_GRN" "$C_RESET"
  printf '%s  ✔%s Pause pod overprovisioning terpasang\n'                           "$C_GRN" "$C_RESET"
  echo
  printf '%sHasil penting:%s\n' "$C_BOLD" "$C_RESET"
  echo "  Project        : $PROJECT_ID"
  echo "  Zone           : $ZONE"
  echo "  Jumlah node    : $NODE_COUNT"
  echo "  Node pool      : ${POOLS:-default-pool}"
  echo "  php-apache     : ${PHP_REP:--} replika"
  echo "  hello-server   : CPU request ${HELLO_CPU:--}"
  echo
  typeout "Jangan lupa mampir ke GitHub saya: https://github.com/Jutapen"
  echo
  printf '%sCredit: Jutapen%s\n' "$C_BOLD" "$C_RESET"
}

main "$@"
