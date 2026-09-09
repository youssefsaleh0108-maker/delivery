#!/bin/sh
# Bring the box back after the node stopped answering, and keep it back.
#
#   ssh delivery-vps 'sh -s' < infra/recover-node.sh
#
# Run this as soon as SSH answers after a reboot — ideally before the pods have finished starting,
# which is the window in which the node is least loaded.
#
# WHY THIS EXISTS. The platform ran for hours and then stopped answering entirely: TCP was still
# accepted on 80 and 443 by k3s's host-port listener, while neither Traefik nor sshd could get
# scheduled. The cause was a change to JAVA_OPTS that swapped SerialGC and C1 for G1 and full
# tiered compilation, without touching the two numbers around them:
#
#   * These pods have no CPU limits, so every JVM sees all 8 cores and sizes its GC and compiler
#     thread pools for 8. One collection thread became roughly eight, across twenty-two processes.
#   * MaxRAMPercentage=70 of a 512Mi limit leaves ~154Mi outside the heap. That fits C1 and
#     SerialGC; it does not fit G1's region metadata and remembered sets plus a C2-sized code
#     cache plus those threads. Pods drift past the limit, get OOMKilled, restart, and
#     twenty-two doing that at once takes the node with them.
#
# A reboot alone is NOT enough: the ConfigMap in the cluster still holds the bad value, so the
# pods come back exactly as they were and the node goes down again. This patches it first.
set -u

GOOD='-XX:MaxRAMPercentage=70 -XX:+UseContainerSupport -XX:TieredStopAtLevel=1 -XX:+UseSerialGC -Xss512k'

echo "== node =="
uptime
free -m | head -2

echo
echo "== stop the bleeding: pin the JVM flags back in both environments =="
for NS in delivery-dev delivery-qa; do
  kubectl -n "$NS" patch configmap platform-common --type merge \
    -p "{\"data\":{\"JAVA_OPTS\":\"$GOOD\"}}" && echo "  $NS patched"
done

echo
echo "== roll the services onto it =="
# A ConfigMap change does not restart a pod on its own, so nothing above has taken effect yet.
for NS in delivery-dev delivery-qa; do
  for D in $(kubectl -n "$NS" get deploy -o name 2>/dev/null); do
    kubectl -n "$NS" rollout restart "$D" >/dev/null 2>&1
  done
  echo "  $NS restarting"
done

echo
echo "== settle =="
# Deliberately not waiting on every rollout in parallel: the thing that broke the node was
# twenty-two JVMs starting at once, and there is no reason to reproduce it while recovering.
sleep 60
for NS in delivery-dev delivery-qa; do
  READY=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -cE ' (1/1|2/2) +Running')
  TOTAL=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | grep -vc 'Completed')
  echo "  $NS $READY/$TOTAL ready"
done

echo
echo "== anything OOMKilled since boot =="
kubectl get pods -A -o json 2>/dev/null \
  | grep -o '"reason":"OOMKilled"' | wc -l | sed 's/^/  OOMKilled container states: /'

echo
echo "Argo will sync the same value from git (all three branches carry the revert), so this"
echo "patch and the repository now agree and selfHeal will not undo it."
