# Task 11 — Kubernetes Scheduling: Validation Instructions

## Prerequisites

Install Docker Desktop, `kind`, and `kubectl`. Run the following commands from the root of this repository. Make sure Docker Desktop has sufficient CPU and memory for five Kubernetes nodes, MySQL, and the Django application.

This task uses one control-plane node and **four worker nodes**. The example cluster name is `scheduling`. The `bootstrap.sh` script expects exactly four worker nodes and assigns scheduling labels and taints to them.

> **Note:** If another local kind cluster already uses host ports 80, 443, 30007, or 30008, creating a second cluster with the same `extraPortMappings` will fail. Port mappings are not needed for this scheduling exercise; remove those mappings from the task's `cluster.yml`, or otherwise avoid port conflicts. Do not delete other clusters unnecessarily.

## 1. Create and select the cluster

```bash
kind create cluster --name scheduling --config cluster.yml
kubectl config use-context kind-scheduling
kubectl get nodes -o wide
```

If the cluster already exists, skip the creation command. Confirm that the current context is `kind-scheduling` and that **five nodes** are in the `Ready` state:

```bash
kubectl config current-context
kubectl get nodes
```

The node names in the examples below begin with `scheduling-`. Other cluster names result in different node names.

## 2. Deploy the application and configure scheduling

Run the provided bootstrap script:

```bash
bash bootstrap.sh
```

The updated script should perform the following operations:

1. Identify four worker nodes (excluding the control-plane node).
2. Label three workers with `app=mysql` and taint them with `app=mysql:NoSchedule`.
3. Label the remaining worker with `app=todoapp`.
4. Deploy the MySQL Namespace, ConfigMap, Secret, Service, and StatefulSet.
5. Wait for the MySQL StatefulSet to become ready.
6. Deploy the Django Namespace, storage resources, Secret, ConfigMap, Services, and Deployment. The HPA is intentionally excluded from this task to avoid scaling conflicts with the required Pod Anti-Affinity rules.
7. Wait for the Django Deployment to become ready.

The script can be rerun in the same cluster. If you are using a separate or older bootstrap script, make sure it actually applies the scheduling settings; existing labels and taints from an earlier session do not prove that a clean deployment is reproducible.

## 3. Verify node labels and taints

```bash
kubectl get nodes -L app
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}'
```

Expected configuration:

- Three worker nodes have label `app=mysql` and taint `app=mysql:NoSchedule`.
- One worker node has label `app=todoapp`.
- The control-plane node retains its normal `node-role.kubernetes.io/control-plane:NoSchedule` taint.

The exact worker names may differ depending on the cluster and the bootstrap script's ordering.

## 4. Validate MySQL StatefulSet scheduling

Check StatefulSet readiness and Pod placement:

```bash
kubectl get statefulset mysql -n mysql
kubectl get pods -n mysql -o wide
kubectl get pvc -n mysql
```

The repository's MySQL StatefulSet is configured with **two replicas**. Expect `mysql-0` and `mysql-1` to become `1/1 Running` and to be assigned to **different worker nodes**, each labeled `app=mysql`.

Inspect the StatefulSet's scheduling configuration:

```bash
kubectl get statefulset mysql -n mysql -o yaml
```

Under `spec.template.spec`, verify:

- `tolerations` matches `key: app`, `value: mysql`, `effect: NoSchedule`.
- Required `nodeAffinity` selects nodes labeled `app=mysql`.
- Required `podAntiAffinity` selects other Pods labeled `app=mysql` and uses `topologyKey: kubernetes.io/hostname`.

A matching toleration permits a Pod to use a tainted node, but does not force it to be scheduled there. Required node affinity restricts eligible nodes, and required Pod anti-affinity prevents the two MySQL replicas from sharing a node.

## 5. Validate Django Deployment scheduling

```bash
kubectl get deployment todoapp -n todoapp
kubectl get pods -n todoapp -o wide
kubectl get deployment todoapp -n todoapp -o yaml
```

Verify the following fields in `spec.template.spec.affinity`:

- `nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution` prefers nodes labeled `app=todoapp` (for example, with `weight: 100`).
- `podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution` selects Pods labeled `app=todoapp` and specifies `topologyKey: kubernetes.io/hostname`.

With the four-worker layout described above, a single Django Pod should normally run on the worker labeled `app=todoapp`. Preferred node affinity is **not a strict requirement**; it does not guarantee placement on that node in every cluster.

Check health and readiness:

```bash
kubectl get pods -n todoapp
kubectl logs -n todoapp deployment/todoapp --tail=50
```

Wait until the application Pod is `1/1 Running`. Immediately after startup, `/api/ready` may temporarily fail while Django performs migrations or initializes; inspect logs and Pod events if it does not recover.

## 6. Validate required Pod anti-affinity (optional scheduling test)

The default Django Deployment has one replica, so its Pod anti-affinity is easiest to observe by temporarily requesting two Pods. **This test intentionally creates a Pending Pod in the four-worker layout**: the only worker available to Django already hosts the first Django Pod, while the other three workers have MySQL taints that Django does not tolerate.

```bash
kubectl scale deployment/todoapp -n todoapp --replicas=2
kubectl get pods -n todoapp -o wide
```

Expect one Django Pod to remain `Running` and the second to be `Pending`. Find the exact reason in the Pending Pod's events:

```bash
kubectl describe pod <PENDING_POD_NAME> -n todoapp
```

This behavior reflects the combination of required Pod anti-affinity and the worker taints, not a broken Deployment. Restore the intended single replica afterwards:

```bash
kubectl scale deployment/todoapp -n todoapp --replicas=1
kubectl get pods -n todoapp -o wide
```

**Important:** If an HPA is enabled, it may later modify the number of replicas. Check `kubectl get hpa -n todoapp` when investigating unexpected replica counts. For this assignment, a Pending Pod from a scale test is not proof of a defect unless the scheduling rules are violated.

## 7. Troubleshooting

If a Pod remains `Pending`, inspect its events and the node state:

```bash
kubectl get pods -A -o wide
kubectl describe pod <POD_NAME> -n <NAMESPACE>
kubectl get nodes -L app
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}'
```

Typical scheduling errors include untolerated taints, missing node labels, and required Pod anti-affinity conflicts. If a Pod is `Running` but not `Ready`, check application logs and probe failures; this is different from a scheduling failure.

## 8. Submission

Ensure the Pull Request includes the modified MySQL StatefulSet, Django Deployment, `bootstrap.sh`, and this `INSTRUCTION.md`. Do not commit credentials or locally generated cluster state.

```bash
git status
git add .infrastructure/mysql/statefulSet.yml .infrastructure/app/deployment.yml bootstrap.sh INSTRUCTION.md
git commit -m "Configure Kubernetes taints tolerations and affinity"
git push origin HEAD
```

Open or update a Pull Request and submit its URL on the Mate Academy platform. The reviewer should follow the steps above in a fresh cluster to validate reproducibility.
