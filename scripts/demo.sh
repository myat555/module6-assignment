#!/usr/bin/env bash
# Runs the three lab experiments and saves terminal output to evidence/.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence

CLIENT=deployment/inventory-client
run() { echo "\$ $*"; "$@"; echo; }
inv_pods() { kubectl get pods -l app=inventory -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'; }
# Show each Service backend and whether the EndpointSlice marks it ready.
endpoints() {
  echo "\$ kubectl get endpointslices -l kubernetes.io/service-name=inventory-service (ip / pod / ready)"
  kubectl get endpointslices -l kubernetes.io/service-name=inventory-service \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{"\t"}{.targetRef.name}{"\tready="}{.conditions.ready}{"\n"}{end}'
  echo
}
# Tally which Pod served the client's requests over the last N seconds.
tally() {
  echo "\$ kubectl logs $CLIENT --since=${1}s | grep -o 'served_by=[^ ]*' | sort | uniq -c"
  kubectl logs "$CLIENT" --since="${1}s" | grep -o 'served_by=[^ ]*' | sort | uniq -c
  echo
}

# ---------------------------------------------------------------- Part 1
{
  echo "=== PART 1: Deployment, Service, and load balancing ==="
  run kubectl get deploy inventory inventory-client
  run kubectl get pods -o wide
  run kubectl get svc inventory-service
  endpoints
  echo "# Client resolves the Service name through cluster DNS:"
  run kubectl exec "$CLIENT" -- python -c "import socket; print('inventory-service ->', socket.gethostbyname('inventory-service'))"
  echo "# One request through the Service name from inside the client Pod:"
  run kubectl exec "$CLIENT" -- python -c "import urllib.request; print(urllib.request.urlopen('http://inventory-service/items').read().decode())"
  sleep 20
  echo "# Client log (last 10 lines):"
  run kubectl logs "$CLIENT" --tail=10
  echo "# Requests per replica over the last 20 seconds:"
  tally 20
} 2>&1 | tee evidence/part1-deploy.txt

# ---------------------------------------------------------------- Part 2
{
  echo "=== PART 2: Readiness failure and recovery ==="
  read -r POD_A POD_B <<<"$(inv_pods | tr '\n' ' ')"
  echo "# Making $POD_A fail its readiness probe"
  run kubectl exec "$POD_A" -- touch /tmp/unready
  sleep 6
  run kubectl get pods -l app=inventory -o wide
  endpoints
  echo "\$ kubectl describe pod $POD_A | grep -E 'Status:|Ready:|Restart Count|Readiness probe failed'"
  kubectl describe pod "$POD_A" | grep -E "^Status:|  Ready:|Restart Count|Readiness probe failed"
  echo
  echo "# Pod is still running - it answers directly on its own IP:"
  POD_A_IP=$(kubectl get pod "$POD_A" -o jsonpath='{.status.podIP}')
  run kubectl exec "$CLIENT" -- python -c "import urllib.request; print(urllib.request.urlopen('http://$POD_A_IP:8080/healthz').read().decode())"
  sleep 15
  echo "# Requests per replica during the 15s that $POD_A was unready:"
  tally 15

  echo "# Restoring readiness on $POD_A"
  run kubectl exec "$POD_A" -- rm /tmp/unready
  sleep 6
  run kubectl get pods -l app=inventory -o wide
  endpoints
  sleep 15
  echo "# Requests per replica in the 15s after recovery:"
  tally 15
} 2>&1 | tee evidence/part2-readiness.txt

# ---------------------------------------------------------------- Part 3
{
  echo "=== PART 3: Pod deletion and replacement ==="
  run kubectl get svc inventory-service
  run kubectl get pods -l app=inventory -o wide
  VICTIM=$(inv_pods | head -1)
  echo "# Deleting $VICTIM"
  run kubectl delete pod "$VICTIM" --wait=false
  run kubectl get pods -l app=inventory -o wide
  kubectl rollout status deployment/inventory --timeout=120s
  sleep 5
  echo
  echo "# After recovery:"
  run kubectl get pods -l app=inventory -o wide
  run kubectl get svc inventory-service
  endpoints
  echo "# ReplicaSet events showing the replacement:"
  kubectl get events --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp | tail -4
  echo
  sleep 15
  echo "# Client log across the deletion (last 40s):"
  run kubectl logs "$CLIENT" --since=40s
  echo "# Requests per replica in the last 15s (new Pod is serving):"
  tally 15
} 2>&1 | tee evidence/part3-pod-replacement.txt
