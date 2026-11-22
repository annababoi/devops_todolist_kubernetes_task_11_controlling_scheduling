#!/bin/bash
set -e

# Configure Node labels and taints
echo "Configuring Kubernetes scheduling..."

workers=($(kubectl get nodes \
  -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort))

if [ "${#workers[@]}" -ne 4 ]; then
  echo "Error: Expected exactly 4 worker nodes."
  exit 1
fi

# Three worker nodes for MySQL
for node in "${workers[@]:0:3}"; do
  kubectl label node "$node" app=mysql --overwrite
  kubectl taint node "$node" app=mysql:NoSchedule --overwrite
done

# One worker node for Django
kubectl label node "${workers[3]}" app=todoapp --overwrite

# Deploy MySQL
kubectl apply -f .infrastructure/mysql/ns.yml
kubectl apply -f .infrastructure/mysql/configMap.yml
kubectl apply -f .infrastructure/mysql/secret.yml
kubectl apply -f .infrastructure/mysql/service.yml
kubectl apply -f .infrastructure/mysql/statefulSet.yml

# Wait for MySQL
kubectl rollout status statefulset/mysql \
  -n mysql --timeout=300s

# Deploy Django ToDo App
kubectl apply -f .infrastructure/app/ns.yml
kubectl apply -f .infrastructure/app/pv.yml
kubectl apply -f .infrastructure/app/pvc.yml
kubectl apply -f .infrastructure/app/secret.yml
kubectl apply -f .infrastructure/app/configMap.yml
kubectl apply -f .infrastructure/app/clusterIp.yml
kubectl apply -f .infrastructure/app/nodeport.yml
#kubectl apply -f .infrastructure/app/hpa.yml
kubectl apply -f .infrastructure/app/deployment.yml

# Wait for Django
kubectl rollout status deployment/todoapp \
  -n todoapp --timeout=300s

# Verify resources
kubectl get nodes -L app
kubectl get pods -n mysql -o wide
kubectl get pods -n todoapp -o wide

echo "Deployment completed."
