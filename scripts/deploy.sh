#!/usr/bin/env bash
# Creates a kind cluster (if missing), builds the image, and deploys everything.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=inventory-lab
IMAGE=inventory-app:1.0

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER"
fi
kubectl config use-context "kind-$CLUSTER"

docker build -t "$IMAGE" app
kind load docker-image "$IMAGE" --name "$CLUSTER"

kubectl apply -f k8s/inventory.yaml
kubectl rollout status deployment/inventory --timeout=120s
kubectl apply -f k8s/client.yaml
kubectl rollout status deployment/inventory-client --timeout=120s

kubectl get deploy,pods,svc,endpoints -o wide
