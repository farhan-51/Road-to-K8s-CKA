# Kubernetes CKA Learning Blueprint

Audience: you already know Linux and containers, so this plan skips generic container fundamentals and focuses on Kubernetes administration, CKA speed, and production-style workflows.

Verified against the official Linux Foundation CKA page on 2026-07-09: current exam domains are Cluster Architecture, Installation & Configuration 25%; Workloads & Scheduling 15%; Services & Networking 20%; Storage 10%; Troubleshooting 30%. The exam is performance-based, 2 hours, and currently aligned to Kubernetes v1.35.

Official references:
- CKA exam domains and details: https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/
- kubectl on macOS: https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/
- kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/
- Helm install: https://helm.sh/docs/intro/install/
- Flux install: https://fluxcd.io/flux/installation/
- Docker Desktop on Mac: https://docs.docker.com/desktop/setup/install/mac-install/

## 1. Local Environment Setup on macOS

### Recommended local topology

Use Docker Desktop as the container runtime, kind as the daily lab cluster, kubectl for exam operations, Helm for package-based installation, and Flux for GitOps. Leave Docker Desktop's built-in Kubernetes disabled unless you specifically want a second local cluster.

For Docker Desktop resources, start with 4 CPUs, 8 GB RAM, and 40-60 GB disk. Multi-node kind clusters and image pulls are much smoother with 8 GB RAM allocated.

### Step-by-step installation

```bash
# 1. Install Homebrew if needed.
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Install Docker Desktop.
brew install --cask docker
open -a Docker

# Wait until Docker Desktop says it is running, then verify:
docker version
docker run --rm hello-world

# 3. Install Kubernetes tooling.
brew install kubectl kind helm fluxcd/tap/flux

# Optional but useful for CKA speed.
brew install k9s stern yq jq
```

Add shell completion and exam aliases to `~/.zshrc`:

```bash
alias k=kubectl
alias kg='kubectl get'
alias kd='kubectl describe'
alias ka='kubectl apply -f'
alias kn='kubectl config set-context --current --namespace'
export do='--dry-run=client -o yaml'
source <(kubectl completion zsh)
compdef __start_kubectl k
```

Create a reusable multi-node kind cluster:

```bash
cat > /tmp/cka-kind.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
    protocol: TCP
- role: worker
- role: worker
YAML

kind create cluster --name cka-lab --config /tmp/cka-kind.yaml --wait 120s
kubectl config use-context kind-cka-lab
kubectl get nodes -o wide
```

Run the validation script from this repo:

```bash
chmod +x scripts/validate-k8s-env.sh
./scripts/validate-k8s-env.sh
```

## 2. Day-by-Day CKA Curriculum

Pace: 30 days, 1.5-2.5 hours/day. Every fifth day includes mixed practice because CKA rewards fast diagnosis more than passive recall.

### Day 1 - Cluster Mental Model and kubectl Workflow

Domain: Cluster Architecture

Theory: A Kubernetes cluster is a control plane making decisions and worker nodes running Pods. kubectl talks to the API server; everything else reconciles desired state.

Industry standard: Treat YAML as the source of truth, use namespaces for isolation, and keep labels consistent from day one.

Hands-on:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl create ns day1
kubectl -n day1 create deployment hello --image=nginx:1.27 --replicas=2
kubectl -n day1 expose deployment hello --port=80
kubectl -n day1 get all
kubectl -n day1 delete deploy,svc --all
```

Assignments:
- Create namespace `ops`, run `busybox:1.36` with command `sleep 3600`, and prove which node it landed on.
- Generate deployment YAML for `nginx:1.27` without creating it, save it, apply it, then delete it.

### Day 2 - Pods, Namespaces, Labels, and Selectors

Domain: Workloads & Scheduling

Theory: A Pod is the smallest runnable unit. Labels are key-value tags; selectors are how Services, Deployments, and commands find matching objects.

Industry standard: Never rely on object names for grouping; use stable labels such as `app.kubernetes.io/name`, `component`, and `environment`.

Hands-on:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: labeled-nginx
  namespace: day2
  labels:
    app.kubernetes.io/name: nginx
    environment: lab
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
```

```bash
kubectl create ns day2
kubectl apply -f pod.yaml
kubectl -n day2 get pods -l app.kubernetes.io/name=nginx
kubectl -n day2 label pod labeled-nginx tier=frontend
kubectl -n day2 get pod labeled-nginx --show-labels
```

Assignments:
- Create three Pods with labels `tier=frontend` or `tier=backend`; list only backend Pods.
- Change one label in place and verify the selector result changes.

### Day 3 - Deployments, ReplicaSets, Rollouts, Rollbacks

Domain: Workloads & Scheduling

Theory: A Deployment keeps the desired number of app replicas running and safely replaces old Pods with new ones during updates.

Industry standard: Use Deployments for stateless apps, set rollout strategy deliberately, and keep image tags immutable in production.

Hands-on:

```bash
kubectl create ns day3
kubectl -n day3 create deployment web --image=nginx:1.26 --replicas=3
kubectl -n day3 set image deployment/web nginx=nginx:1.27 --record=true
kubectl -n day3 rollout status deployment/web
kubectl -n day3 rollout history deployment/web
kubectl -n day3 rollout undo deployment/web
kubectl -n day3 get rs,pods
```

Assignments:
- Create a Deployment with 4 replicas, update its image, then roll back to the previous version.
- Intentionally set a bad image tag, observe rollout behavior, then repair it.

### Day 4 - ConfigMaps, Secrets, Environment, and Volumes

Domain: Workloads & Scheduling

Theory: ConfigMaps hold non-secret settings; Secrets hold sensitive values. Pods can consume both as environment variables or mounted files.

Industry standard: Do not put real secrets in plain Git. In production use external secret managers or sealed/encrypted secret workflows.

Hands-on:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: day4
data:
  APP_MODE: lab
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: day4
type: Opaque
stringData:
  PASSWORD: change-me
---
apiVersion: v1
kind: Pod
metadata:
  name: config-demo
  namespace: day4
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "env | grep APP_MODE && cat /secret/PASSWORD && sleep 3600"]
    envFrom:
    - configMapRef:
        name: app-config
    volumeMounts:
    - name: secret-volume
      mountPath: /secret
      readOnly: true
  volumes:
  - name: secret-volume
    secret:
      secretName: app-secret
```

Assignments:
- Create a Secret imperatively and consume it as an environment variable.
- Mount a ConfigMap as a file and read it using `kubectl exec`.

### Day 5 - Mixed Workload Drill

Domain: Workloads & Scheduling

Theory: CKA asks you to combine small primitives quickly: namespace, Deployment, Service, labels, env, and rollout.

Industry standard: Prefer declarative YAML for repeatability, but use imperative generation during the exam for speed.

Hands-on:

```bash
kubectl create ns day5
kubectl -n day5 create configmap web-config --from-literal=COLOR=blue
kubectl -n day5 create deployment web --image=nginx:1.27 --replicas=2
kubectl -n day5 expose deployment web --port=80 --target-port=80
kubectl -n day5 set env deployment/web COLOR=blue
kubectl -n day5 rollout status deploy/web
```

Assignments:
- In 8 minutes: create a namespace, Deployment, Service, and ConfigMap, then verify endpoints exist.
- In 5 minutes: break the image, diagnose the error, and fix it.

### Day 6 - Scheduling: nodeSelector, Affinity, Taints, Tolerations

Domain: Workloads & Scheduling

Theory: Scheduling is how Kubernetes chooses a node for a Pod. Constraints narrow where Pods may run.

Industry standard: Use topology spread or affinity for resilience; use taints to reserve nodes for special workloads.

Hands-on:

```bash
kubectl label node $(kubectl get nodes -o name | tail -1 | cut -d/ -f2) disk=fast
kubectl create ns day6
kubectl -n day6 run scheduled --image=nginx:1.27 --overrides='
{
  "spec": {
    "nodeSelector": {"disk": "fast"}
  }
}'
kubectl -n day6 get pod scheduled -o wide
```

Assignments:
- Taint one worker with `dedicated=batch:NoSchedule`; create one Pod that cannot schedule and one that tolerates it.
- Add node affinity requiring `disk=fast` and verify placement.

### Day 7 - Resource Requests, Limits, QoS, and Probes

Domain: Workloads & Scheduling

Theory: Requests reserve capacity for scheduling. Limits cap usage. Probes tell Kubernetes when a container is ready or unhealthy.

Industry standard: Set CPU/memory requests on every production workload; use readiness probes for traffic gating and liveness probes carefully.

Hands-on:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probed-web
  namespace: day7
spec:
  replicas: 2
  selector:
    matchLabels: {app: probed-web}
  template:
    metadata:
      labels: {app: probed-web}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        resources:
          requests: {cpu: 50m, memory: 64Mi}
          limits: {cpu: 200m, memory: 128Mi}
        readinessProbe:
          httpGet: {path: /, port: 80}
          initialDelaySeconds: 3
        livenessProbe:
          httpGet: {path: /, port: 80}
          initialDelaySeconds: 10
```

Assignments:
- Create a Pod that exceeds memory limits and identify `OOMKilled`.
- Add a failing readiness probe, explain why the Pod runs but receives no Service traffic.

### Day 8 - Jobs, CronJobs, DaemonSets, StatefulSets

Domain: Workloads & Scheduling

Theory: Jobs run to completion, CronJobs run on a schedule, DaemonSets run one Pod per node, and StatefulSets provide stable identity.

Industry standard: Use Jobs for migrations and batch work, DaemonSets for node agents, and StatefulSets only when stable network/storage identity matters.

Hands-on:

```bash
kubectl create ns day8
kubectl -n day8 create job pi --image=perl:5.38 -- perl -Mbignum=bpi -wle 'print bpi(20)'
kubectl -n day8 logs job/pi
kubectl -n day8 create cronjob heartbeat --image=busybox:1.36 --schedule='*/5 * * * *' -- sh -c 'date; echo ok'
kubectl -n day8 get cronjob,job,pod
```

Assignments:
- Create a DaemonSet running `busybox sleep 3600` on every node.
- Create a CronJob, manually trigger one Job from it, and inspect logs.

### Day 9 - RBAC and ServiceAccounts

Domain: Cluster Architecture

Theory: RBAC decides who can do what. ServiceAccounts give Pods an identity inside the cluster.

Industry standard: Use least privilege: Role over ClusterRole when possible, read-only verbs unless writes are needed, and separate identities per app.

Hands-on:

```bash
kubectl create ns day9
kubectl -n day9 create serviceaccount viewer
kubectl -n day9 create role pod-reader --verb=get,list,watch --resource=pods
kubectl -n day9 create rolebinding viewer-read-pods --role=pod-reader --serviceaccount=day9:viewer
kubectl auth can-i list pods --as=system:serviceaccount:day9:viewer -n day9
kubectl auth can-i delete pods --as=system:serviceaccount:day9:viewer -n day9
```

Assignments:
- Create a Role that can update ConfigMaps but cannot delete them.
- Bind a ServiceAccount to read Services in only one namespace and prove it cannot read another namespace.

### Day 10 - kubeadm, Control Plane Components, and etcd

Domain: Cluster Architecture

Theory: kubeadm bootstraps clusters. The API server, scheduler, controller manager, kubelet, kube-proxy, CoreDNS, and etcd form the cluster backbone.

Industry standard: Production clusters use HA control planes, external or stacked etcd with backups, and controlled upgrades.

Hands-on:

```bash
kubectl -n kube-system get pods -o wide
kubectl -n kube-system describe pod -l component=kube-apiserver
kubectl get componentstatuses 2>/dev/null || true
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
```

Assignments:
- Find the static Pod manifests inside a kind control-plane node using `docker exec`.
- List all kube-system Pods and map each one to its purpose.

### Day 11 - Cluster Lifecycle, Node Maintenance, Drain/Cordon

Domain: Cluster Architecture

Theory: Node maintenance means preventing new Pods from landing on a node, safely evicting existing Pods, doing work, then bringing it back.

Industry standard: Use PodDisruptionBudgets for critical apps and drain nodes during upgrades or repairs.

Hands-on:

```bash
NODE=$(kubectl get nodes --no-headers | awk '/worker/ {print $1; exit}')
kubectl cordon "$NODE"
kubectl get nodes
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data
kubectl uncordon "$NODE"
```

Assignments:
- Create a Deployment with 3 replicas, drain a worker, and confirm Pods reschedule.
- Create a PodDisruptionBudget that requires at least 2 available Pods, then observe drain behavior.

### Day 12 - Helm Basics

Domain: Cluster Architecture

Theory: Helm packages Kubernetes manifests as charts with values so teams can install and upgrade apps consistently.

Industry standard: Pin chart versions, keep environment-specific values files, and review rendered YAML before production changes.

Hands-on:

```bash
kubectl create ns day12
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install web bitnami/nginx --namespace day12 --version 18.3.5 --set replicaCount=2
helm -n day12 list
helm -n day12 upgrade web bitnami/nginx --version 18.3.5 --set replicaCount=3
helm -n day12 rollback web 1
```

Assignments:
- Render a chart with `helm template` and find the Service type before installing.
- Install, upgrade, rollback, and uninstall a Helm release.

### Day 13 - Kustomize and CRDs/Operators

Domain: Cluster Architecture

Theory: Kustomize patches plain YAML. CRDs extend Kubernetes with new resource types; operators automate domain-specific operations.

Industry standard: Use CRDs carefully because they extend cluster behavior; back them up and understand upgrade order.

Hands-on:

```bash
mkdir -p /tmp/day13/base /tmp/day13/overlay
kubectl create deployment app --image=nginx:1.27 --dry-run=client -o yaml > /tmp/day13/base/deploy.yaml
printf 'resources:\n- deploy.yaml\n' > /tmp/day13/base/kustomization.yaml
cat > /tmp/day13/overlay/kustomization.yaml <<'YAML'
resources:
- ../base
replicas:
- name: app
  count: 2
namePrefix: lab-
YAML
kubectl apply -k /tmp/day13/overlay
kubectl get deploy lab-app
```

Assignments:
- Patch a Deployment image using Kustomize.
- List CRDs in your cluster and explain which component installed them.

### Day 14 - Cluster Architecture Review Drill

Domain: Cluster Architecture

Theory: This domain mixes admin primitives: RBAC, kubeadm concepts, Helm/Kustomize, node lifecycle, CRDs, and control plane awareness.

Industry standard: Production admins automate install/upgrade paths but still need manual debug skills when automation fails.

Hands-on:

```bash
kubectl get nodes,pods -A
kubectl auth can-i '*' '*' --all-namespaces
helm list -A
kubectl api-resources | head
kubectl explain deployment.spec.strategy
```

Assignments:
- In 20 minutes: create RBAC for a read-only app operator, deploy an app with Helm, then cordon and uncordon a node.
- Write a one-page map of the control plane and which commands prove each component is healthy.

### Day 15 - Services, Endpoints, and DNS

Domain: Services & Networking

Theory: A Service gives stable network access to changing Pods. DNS lets apps call `service.namespace.svc.cluster.local` instead of Pod IPs.

Industry standard: Use ClusterIP for internal traffic, avoid direct Pod IP dependencies, and monitor EndpointSlices when Services do not route.

Hands-on:

```bash
kubectl create ns day15
kubectl -n day15 create deployment api --image=nginx:1.27 --replicas=2
kubectl -n day15 expose deployment api --port=80 --target-port=80
kubectl -n day15 run client --image=curlimages/curl:8.11.1 --restart=Never --rm -i -- curl -fsS http://api.day15.svc.cluster.local
kubectl -n day15 get svc,endpoints,endpointslice
```

Assignments:
- Create a Service with a selector that does not match any Pod and diagnose missing endpoints.
- Use `nslookup` from a temporary Pod to resolve a Service name.

### Day 16 - NodePort, LoadBalancer, Port-Forward, Ingress

Domain: Services & Networking

Theory: NodePort exposes a Service on every node; LoadBalancer asks infrastructure for an external address; Ingress routes HTTP into Services.

Industry standard: In cloud production, use LoadBalancer or Gateway/Ingress with a controller, TLS, and explicit routing rules.

Hands-on:

```bash
kubectl create ns day16
kubectl -n day16 create deployment web --image=nginx:1.27
kubectl -n day16 expose deployment web --type=NodePort --port=80 --target-port=80
kubectl -n day16 get svc web
kubectl -n day16 port-forward svc/web 8081:80
```

Assignments:
- Change a Service from ClusterIP to NodePort and test it.
- Install an ingress controller in kind and route `/` to an nginx Service.

### Day 17 - NetworkPolicy

Domain: Services & Networking

Theory: NetworkPolicies are firewall-like rules for Pod traffic. By default, Pods are usually open unless policies select them.

Industry standard: Use default-deny per namespace, then allow only required app-to-app paths. Remember kind default CNI may not enforce NetworkPolicy; use Calico/Cilium for realistic labs.

Hands-on:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-client
  namespace: day17
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: client
    ports:
    - protocol: TCP
      port: 80
```

Assignments:
- Create a default-deny ingress policy for a namespace.
- Allow only Pods labeled `role=frontend` to access Pods labeled `app=api`.

### Day 18 - CoreDNS and Gateway API Awareness

Domain: Services & Networking

Theory: CoreDNS serves cluster DNS. Gateway API is the modern Kubernetes API family for north-south traffic routing.

Industry standard: Treat DNS as critical infrastructure; run enough CoreDNS replicas and use Gateway API where your platform supports it.

Hands-on:

```bash
kubectl -n kube-system get deploy coredns
kubectl -n kube-system get configmap coredns -o yaml
kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes.default.svc.cluster.local
kubectl api-resources | grep -i gateway || true
```

Assignments:
- Break a Service selector and distinguish DNS success from endpoint failure.
- Inspect CoreDNS logs and confirm a DNS query from a test Pod.

### Day 19 - Networking Review Drill

Domain: Services & Networking

Theory: Most networking bugs are selector, endpoint, port, DNS, or policy mistakes.

Industry standard: Debug from both sides: the client Pod and the Service/Endpoint objects.

Hands-on:

```bash
kubectl get svc,endpoints,endpointslice -A
kubectl run netshoot --image=nicolaka/netshoot --restart=Never -- sleep 3600
kubectl exec netshoot -- dig kubernetes.default.svc.cluster.local
kubectl exec netshoot -- curl -k https://kubernetes.default.svc
```

Assignments:
- Given a broken Service, fix selector and targetPort issues in under 10 minutes.
- Create two namespaces and prove cross-namespace Service access using FQDN.

### Day 20 - Volumes, PVs, PVCs, StorageClasses

Domain: Storage

Theory: A PVC is a request for storage. A PV is the actual storage. A StorageClass can create PVs dynamically.

Industry standard: Use dynamic provisioning with cloud CSI drivers, set reclaim policies intentionally, and avoid hostPath except for local labs.

Hands-on:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: web-data
  namespace: day20
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: pvc-demo
  namespace: day20
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo hello > /data/msg; sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: web-data
```

Assignments:
- Create a PVC and verify which StorageClass provisioned it.
- Delete a Pod using a PVC and prove the data survives with a replacement Pod.

### Day 21 - Storage Modes, Reclaim Policies, and Stateful Storage

Domain: Storage

Theory: Access modes decide how a volume can attach. Reclaim policy decides what happens to storage after a claim is deleted.

Industry standard: For databases, use StatefulSets with PVC templates, backups, and storage-class-specific performance settings.

Hands-on:

```bash
kubectl create ns day21
kubectl get storageclass
kubectl explain pv.spec.persistentVolumeReclaimPolicy
kubectl -n day21 create deployment writer --image=busybox:1.36 -- sleep 3600
kubectl -n day21 get pvc,pv
```

Assignments:
- Create a StatefulSet with a volumeClaimTemplate.
- Change a PV reclaim policy from `Delete` to `Retain` and explain the operational impact.

### Day 22 - Troubleshooting Method: Events, Logs, Describe, Exec

Domain: Troubleshooting

Theory: Troubleshooting starts with state, then events, then logs, then live inspection. Kubernetes usually tells you where to look if you read events carefully.

Industry standard: Build a repeatable triage path and avoid random restarts before collecting evidence.

Hands-on:

```bash
kubectl create ns day22
kubectl -n day22 run bad --image=nginx:no-such-tag
kubectl -n day22 get pod bad
kubectl -n day22 describe pod bad
kubectl -n day22 get events --sort-by=.lastTimestamp
kubectl -n day22 set image pod/bad bad=nginx:1.27 || true
```

Assignments:
- Diagnose and fix `ImagePullBackOff`.
- Diagnose a Pod stuck in `Pending` because of an impossible nodeSelector.

### Day 23 - Application Failures: CrashLoopBackOff, Probes, Commands

Domain: Troubleshooting

Theory: CrashLoopBackOff means the container starts and exits repeatedly. The cause is usually app error, bad command, missing config, or probe failure.

Industry standard: Inspect previous logs with `--previous`, verify entrypoint/args, and distinguish app crash from kubelet killing via probes.

Hands-on:

```bash
kubectl create ns day23
kubectl -n day23 run crash --image=busybox:1.36 -- sh -c 'echo failing; exit 1'
kubectl -n day23 get pod crash -w
kubectl -n day23 logs crash --previous
kubectl -n day23 describe pod crash
```

Assignments:
- Fix a CrashLooping Pod by changing its command to `sleep 3600`.
- Create a Deployment with a bad liveness probe, identify restarts, and repair the probe.

### Day 24 - Node and Cluster Component Troubleshooting

Domain: Troubleshooting

Theory: Node failures affect scheduling and running workloads. Control plane failures affect the API and reconciliation.

Industry standard: Check node conditions, kubelet logs, static Pod manifests, and kube-system workloads before changing workloads.

Hands-on:

```bash
kubectl get nodes
kubectl describe node $(kubectl get nodes -o name | head -1 | cut -d/ -f2)
kubectl -n kube-system get pods -o wide
kubectl top nodes || true
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

Assignments:
- Mark a node unschedulable and explain why new Pods avoid it.
- Find all Pods not running cluster-wide and group them by reason.

### Day 25 - Service and DNS Troubleshooting

Domain: Troubleshooting

Theory: If an app cannot connect, test name resolution, Service object, endpoints, targetPort, Pod readiness, and NetworkPolicy in that order.

Industry standard: Keep a debug image available and make no assumptions about port names or selectors.

Hands-on:

```bash
kubectl create ns day25
kubectl -n day25 create deployment api --image=nginx:1.27
kubectl -n day25 expose deployment api --port=8080 --target-port=8080
kubectl -n day25 get svc,endpoints api
kubectl -n day25 describe svc api
kubectl -n day25 patch svc api -p '{"spec":{"ports":[{"port":80,"targetPort":80}]}}'
```

Assignments:
- Break a Service by setting the wrong `targetPort`, then fix it.
- Break a Service by changing Pod labels, then restore endpoints.

### Day 26 - Observability: Metrics, Output Streams, Events

Domain: Troubleshooting

Theory: Kubernetes exposes object state, events, logs, and metrics. Logs answer what the app said; events answer what Kubernetes did.

Industry standard: Production clusters use metrics-server, centralized logs, alerting, and dashboards, but CKA focuses on kubectl-driven inspection.

Hands-on:

```bash
kubectl top pods -A || true
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl describe pod -n kube-system -l k8s-app=kube-dns
```

Assignments:
- Find the highest CPU/memory Pod if metrics are available.
- Capture logs from all Pods matching one label.

### Day 27 - Flux CD GitOps Basics

Domain: Cluster Architecture plus modern workflow

Theory: Flux watches Git and reconciles cluster state to match it. Instead of pushing changes directly to the API, you push to Git.

Industry standard: Use one repo path per environment, protect main branches, and use image automation only after manual GitOps is reliable.

Hands-on:

```bash
flux check --pre
flux install
kubectl -n flux-system get pods
mkdir -p /tmp/flux-lab
kubectl create ns day27 --dry-run=client -o yaml > /tmp/flux-lab/ns.yaml
flux create source git local-lab --url=https://github.com/fluxcd/flux2-kustomize-helm-example --branch=main --interval=1m --export
```

Assignments:
- Install Flux controllers on your lab cluster and verify `flux check`.
- Explain the difference between `GitRepository`, `Kustomization`, `HelmRepository`, and `HelmRelease`.

### Day 28 - Helm with Flux

Domain: Cluster Architecture plus modern workflow

Theory: Flux can reconcile Helm releases from Git, so chart installation and upgrades become auditable Git changes.

Industry standard: Keep Helm values in Git, pin chart versions, and monitor `HelmRelease` readiness.

Hands-on:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  interval: 10m
  url: https://charts.bitnami.com/bitnami
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: day28-nginx
  namespace: flux-system
spec:
  interval: 5m
  targetNamespace: day28
  chart:
    spec:
      chart: nginx
      version: 18.3.5
      sourceRef:
        kind: HelmRepository
        name: bitnami
  install:
    createNamespace: true
  values:
    replicaCount: 2
```

Assignments:
- Apply the HelmRepository and HelmRelease, then inspect reconciliation status.
- Change `replicaCount` and verify Flux updates the workload.

### Day 29 - Full CKA Mock 1

Domain: All domains

Theory: Exam success is speed plus accuracy. Read the task, switch context/namespace, solve, verify, move on.

Industry standard: In production and exams, verification is part of the task. A change is not done until the observed state matches intent.

Hands-on:

```bash
kubectl config get-contexts
kubectl config current-context
kubectl get ns
kubectl api-resources --namespaced=true
kubectl explain deployment.spec.template.spec.containers.resources
```

Assignments:
- 60-minute mock: 12 tasks covering Deployment, Service, RBAC, scheduling, storage, logs, and node maintenance.
- Review every miss and write the exact command you should have used.

### Day 30 - Full CKA Mock 2 and Final Review

Domain: All domains

Theory: Your final goal is not memorizing YAML; it is navigating Kubernetes resources under time pressure.

Industry standard: Keep changes small, reversible, and verified. The same habit works in production incidents.

Hands-on:

```bash
kubectl create ns final
kubectl -n final create deployment web --image=nginx:1.27 --replicas=3
kubectl -n final expose deploy web --port=80
kubectl -n final get deploy,rs,pod,svc,endpoints -o wide
kubectl -n final rollout restart deploy/web
kubectl -n final rollout status deploy/web
```

Assignments:
- 90-minute mock: 17-20 tasks, no notes except your cheat sheet and official docs.
- Repeat all failed tasks until each can be solved twice without hints.

## 3. Troubleshooting and Common Pitfalls

### Universal triage flow

```bash
kubectl get pod -A
kubectl -n <ns> get pod <pod> -o wide
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --all-containers
kubectl -n <ns> logs <pod> --previous
kubectl -n <ns> get events --sort-by=.lastTimestamp
kubectl -n <ns> exec -it <pod> -- sh
```

### ImagePullBackOff / ErrImagePull

Common causes: wrong image name, wrong tag, private registry auth missing, registry unreachable, `latest` pull behavior surprises.

Triage and fix:

```bash
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> get events --sort-by=.lastTimestamp
kubectl -n <ns> set image deploy/<deploy> <container>=nginx:1.27
kubectl -n <ns> create secret docker-registry regcred --docker-server=<server> --docker-username=<user> --docker-password=<pass>
kubectl -n <ns> patch serviceaccount default -p '{"imagePullSecrets":[{"name":"regcred"}]}'
```

### CrashLoopBackOff

Common causes: process exits, bad command/args, missing env/config file, failed DB dependency, liveness probe killing the container.

Triage and fix:

```bash
kubectl -n <ns> logs <pod> --previous
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> get pod <pod> -o yaml | less
kubectl -n <ns> edit deploy/<deploy>
kubectl -n <ns> rollout status deploy/<deploy>
```

### Pending Pods

Common causes: insufficient CPU/memory, unbound PVC, taints without tolerations, bad nodeSelector/affinity, no available nodes.

Triage and fix:

```bash
kubectl -n <ns> describe pod <pod>
kubectl describe nodes
kubectl get taints nodes -o custom-columns=NODE:.metadata.name,TAINTS:.spec.taints
kubectl -n <ns> get pvc
kubectl -n <ns> edit deploy/<deploy>
```

### Service Not Working

Common causes: selector mismatch, wrong targetPort, Pods not Ready, NetworkPolicy blocking, DNS misunderstanding.

Triage and fix:

```bash
kubectl -n <ns> get svc <svc> -o yaml
kubectl -n <ns> get endpoints <svc>
kubectl -n <ns> get endpointslice -l kubernetes.io/service-name=<svc>
kubectl -n <ns> get pods --show-labels
kubectl -n <ns> describe svc <svc>
kubectl -n <ns> run curl --image=curlimages/curl:8.11.1 --restart=Never --rm -i -- curl -v http://<svc>:<port>
```

### DNS Failure

Common causes: CoreDNS down, wrong namespace/FQDN, Service has no endpoints, Pod DNS policy modified.

Triage and fix:

```bash
kubectl -n kube-system get deploy,pod -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=100
kubectl run dns --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes.default.svc.cluster.local
kubectl -n <ns> get svc,endpoints
```

### PVC Pending

Common causes: no default StorageClass, bad storageClassName, unsupported access mode, provisioner missing.

Triage and fix:

```bash
kubectl -n <ns> describe pvc <pvc>
kubectl get storageclass
kubectl get pv
kubectl -n <ns> get events --sort-by=.lastTimestamp
kubectl patch storageclass <sc> -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### RBAC Forbidden

Common causes: wrong namespace, RoleBinding subject typo, using Role when ClusterRole is needed, missing verb.

Triage and fix:

```bash
kubectl auth can-i <verb> <resource> -n <ns> --as=<user-or-sa>
kubectl -n <ns> get role,rolebinding
kubectl get clusterrole,clusterrolebinding
kubectl -n <ns> describe rolebinding <name>
```

### Node NotReady

Common causes: kubelet stopped, CNI failure, disk/memory pressure, runtime failure, network issue.

Triage and fix:

```bash
kubectl describe node <node>
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl -n kube-system get pods -o wide
kubectl top node <node> || true
# On real Linux nodes:
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100 --no-pager
sudo crictl ps -a
```

### Helm Failure

Common causes: wrong namespace, chart version mismatch, values typo, CRDs missing, release stuck.

Triage and fix:

```bash
helm list -A
helm -n <ns> status <release>
helm -n <ns> history <release>
helm -n <ns> get values <release>
helm template <release> <chart> -f values.yaml
helm -n <ns> rollback <release> <revision>
```

### Flux Failure

Common causes: Git auth problem, bad path, invalid YAML, Helm chart unavailable, reconciliation suspended.

Triage and fix:

```bash
flux check
flux get sources git -A
flux get kustomizations -A
flux get helmreleases -A
flux logs --all-namespaces --level=error
kubectl -n flux-system describe gitrepository <name>
kubectl -n flux-system describe kustomization <name>
flux reconcile kustomization <name> -n flux-system --with-source
```

## 4. CKA Exam Cheat Sheet

### Shell setup

```bash
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'
source <(kubectl completion bash)  # or zsh
complete -o default -F __start_kubectl k
```

### Context and namespace

```bash
k config get-contexts
k config use-context <ctx>
k config set-context --current --namespace=<ns>
k create ns <ns>
k get ns
```

### Fast object creation

```bash
k run pod1 --image=nginx:1.27
k run pod1 --image=busybox:1.36 --restart=Never -- sleep 3600
k create deploy web --image=nginx:1.27 --replicas=3
k expose deploy web --port=80 --target-port=80
k create service clusterip web --tcp=80:80
k create configmap app-cm --from-literal=MODE=prod
k create secret generic app-secret --from-literal=password=s3cr3t
```

### Generate YAML quickly

```bash
k run pod1 --image=nginx:1.27 $do > pod.yaml
k create deploy web --image=nginx:1.27 --replicas=3 $do > deploy.yaml
k expose deploy web --port=80 --target-port=80 $do > svc.yaml
k create job batch --image=busybox:1.36 -- sh -c 'echo ok' $do > job.yaml
k create cronjob backup --image=busybox:1.36 --schedule='*/5 * * * *' -- date $do > cj.yaml
```

### Inspect and explain

```bash
k get all -n <ns>
k get pod -o wide
k get pod --show-labels
k describe pod <pod>
k logs <pod>
k logs <pod> --previous
k exec -it <pod> -- sh
k explain pod.spec.containers
k api-resources
```

### Labels and annotations

```bash
k label pod <pod> app=web
k label pod <pod> app-
k annotate pod <pod> owner=platform
k get pod -l app=web
```

### Deployments and rollouts

```bash
k scale deploy web --replicas=5
k set image deploy/web nginx=nginx:1.27
k rollout status deploy/web
k rollout history deploy/web
k rollout undo deploy/web
k rollout restart deploy/web
```

### Scheduling

```bash
k label node <node> disk=fast
k taint node <node> dedicated=batch:NoSchedule
k taint node <node> dedicated=batch:NoSchedule-
k cordon <node>
k drain <node> --ignore-daemonsets --delete-emptydir-data
k uncordon <node>
```

### RBAC

```bash
k create sa app-sa -n <ns>
k create role pod-reader --verb=get,list,watch --resource=pods -n <ns>
k create rolebinding read-pods --role=pod-reader --serviceaccount=<ns>:app-sa -n <ns>
k auth can-i list pods --as=system:serviceaccount:<ns>:app-sa -n <ns>
```

### Networking

```bash
k get svc,endpoints,endpointslice
k describe svc <svc>
k port-forward svc/<svc> 8080:80
k run curl --image=curlimages/curl:8.11.1 --restart=Never --rm -i -- curl -v http://<svc>:<port>
k run dns --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes.default
```

### Storage

```bash
k get sc
k get pv,pvc -A
k describe pvc <pvc>
k patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

### Troubleshooting speed path

```bash
k get pod -A | grep -v Running
k describe pod <pod> -n <ns>
k logs <pod> -n <ns> --all-containers
k logs <pod> -n <ns> --previous
k get events -n <ns> --sort-by=.lastTimestamp
k get nodes
k describe node <node>
k -n kube-system get pods
```

### Helm and Flux quick commands

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install web bitnami/nginx -n web --create-namespace --version 18.3.5
helm upgrade web bitnami/nginx -n web --set replicaCount=3
helm rollback web 1 -n web

flux check --pre
flux install
flux check
flux get all -A
flux logs --all-namespaces --level=error
flux reconcile kustomization <name> -n flux-system --with-source
```

