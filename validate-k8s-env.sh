#!/usr/bin/env bash
set -euo pipefail

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing: $1"
    exit 1
  fi
}

echo "Checking local Kubernetes toolchain..."
for bin in docker kind kubectl helm flux; do
  need "$bin"
done

echo
echo "Versions:"
docker --version
kind --version
kubectl version --client=true
helm version --short
flux --version

echo
echo "Checking Docker daemon..."
docker info >/dev/null
docker run --rm hello-world >/dev/null
echo "Docker OK"

CLUSTER_NAME="${CLUSTER_NAME:-cka-lab}"

echo
echo "Checking kind cluster: ${CLUSTER_NAME}"
if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --wait 120s
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
kubectl cluster-info
kubectl get nodes -o wide

echo
echo "Deploying smoke-test workload..."
kubectl create ns env-check --dry-run=client -o yaml | kubectl apply -f -
kubectl -n env-check create deployment web --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml | kubectl apply -f -
kubectl -n env-check expose deployment web --port=80 --target-port=80 --dry-run=client -o yaml | kubectl apply -f -
kubectl -n env-check rollout status deploy/web --timeout=120s
kubectl -n env-check run curl --image=curlimages/curl:8.11.1 --restart=Never --rm -i --quiet -- curl -fsS http://web

echo
echo "Checking Helm..."
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null
helm template env-check bitnami/nginx --version 18.3.5 >/dev/null
echo "Helm OK"

echo
echo "Checking Flux preflight..."
flux check --pre

echo
echo "All checks passed."
