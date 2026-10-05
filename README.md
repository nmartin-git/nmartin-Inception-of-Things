# Inception-of-Things

## Inception of Things - Part 1: K3s Lightweight Cluster

This project provisions a multi-node, lightweight Kubernetes (K3s) cluster from scratch using Vagrant. It serves as a solid Infrastructure as Code (IaC) foundation, focusing on network isolation, resource efficiency, and automated provisioning.

### 🏗️ Architecture & Specifications

The environment follows strict predefined infrastructure requirements:
- **Hypervisor**: VirtualBox managed via Vagrant.
- **Operating System**: Debian 12 (Bookworm) - *Selected as the latest stable official Vagrant box fully compatible with VirtualBox.*
- **Network**: Isolated Host-Only network (`192.168.56.0/24`) to ensure a private and secured network.
- **Hardware Limits**: Strictly bridled to 1 vCPU and 1024 MB RAM per node to enforce lightweight operations.

#### Nodes Organization
| Node Role | Hostname (Suffix) | IP Address | K3s Mode |
| :--- | :--- | :--- | :--- |
| **Control Plane** | `<login>S` | `192.168.56.110` | Server |
| **Agent Worker** | `<login>SW` | `192.168.56.111` | Agent |

### 🛠️ Key Engineering Decisions

1. **Script automation**: Both nodes are provisioned fully automatically through Bash scripts (`server.sh` and `worker.sh`). No manual intervention required.
2. **Secure Token Distribution**: Instead of hardcoding the Kubernetes cluster token, the control plane generates it dynamically. The token is then securely passed to the worker node by Vagrant's default `/vagrant` synchronized folder, ensuring credentials are never exposed in the scripts.
3. **Environment-Driven Configuration**: K3s configurations (such as `K3S_URL` and `K3S_TOKEN_FILE`) are injected via environment variables prior to installation, maintaining clean and efficient execution scripts.
4. **Modern Kubernetes Standards**: The control plane uses the modern `control-plane` role nomenclature, fully compliant with v1.24+ Kubernetes versions.

### 📂 Project Structure

```text
p1/
├── Vagrantfile          # Defines infrastructure, network, and limits
└── scripts/
    ├── server.sh        # Provisions the K3s control plane
    └── worker.sh         # Joins the K3s agent to the cluster
```

### 🚀 How to Run

Clone the repository and navigate to the p1 directory.

Start the infrastructure:

```bash
vagrant up
```

Verify the cluster status. SSH into the control plane and check the nodes:

```bash
vagrant ssh <login>S
sudo kubectl get nodes -o wide
```

Both nodes should appear with a `Ready` status.

## Inception of Things - Part 2: K3s and Three Web Applications

This part builds on Part 1 and deploys a single-node K3s server hosting three web applications, all reachable through **one IP address**. An Ingress routes each request to the right application depending on the `Host` header sent by the client.

### 🏗️ Architecture & Specifications

- **Hypervisor:** VirtualBox managed via Vagrant.
- **Operating System:** Debian 12 (Bookworm).
- **Network:** Isolated Host-Only network (`192.168.56.0/24`).
- **Hardware Limits:** 2 vCPUs and 2048 MB RAM (heavier workload than in Part 1).

| Node Role     | Hostname   | IP Address       | K3s Mode |
|---------------|------------|------------------|----------|
| Control Plane | `<login>S` | `192.168.56.110` | Server   |

### 🌐 Routing Overview

| Request                                 | Routed to      | Replicas |
|-----------------------------------------|----------------|----------|
| `Host: app1.com`                        | `app1-service` | 1        |
| `Host: app2.com`                        | `app2-service` | 3        |
| Any other host / no host (default rule) | `app3-service` | 1        |

### 🛠️ Key Engineering Decisions

- **Script automation:** `server.sh` installs K3s in `server` mode with no manual intervention.
- **API bound to the static IP:** the Kubernetes API and node IP are bound to `192.168.56.110`, so the cluster is only reachable through the private network.
- **Built-in Ingress controller:** K3s ships with Traefik, so no extra controller needs to be installed.
- **Host-based routing:** a single Ingress with three rules. The last rule has **no `host` field**, which makes it the catch-all pointing to app3.
- **Load balancing:** app2 runs with 3 replicas behind a Kubernetes Service, which spreads requests across the pods.
- **Declarative manifests:** every application is described in YAML and applied with `kubectl apply`.

### 📂 Project Structure

```text
p2/
├── Vagrantfile          # VM definition: 2 CPUs, 2GB RAM, static IP
├── scripts/
│   └── server.sh        # Installs K3s (server mode) on 192.168.56.110
└── confs/
    ├── app1.yaml        # Deployment + Service (1 replica)
    ├── app2.yaml        # Deployment + Service (3 replicas)
    ├── app3.yaml        # Deployment + Service (1 replica)
    └── ingress.yaml     # Host-based routing rules
```

### 🚀 How to Run

Navigate to the `p2` directory and start the infrastructure:

```bash
cd p2
vagrant up
```

SSH into the server and apply the manifests (skip this if the provisioning already does it):

```bash
vagrant ssh <login>S
sudo kubectl apply -f /vagrant/confs/
```

### ✅ Verification

Check the node, the pods and the Ingress:

```bash
sudo kubectl get nodes -o wide   # Ready, control-plane,master
sudo kubectl get pods            # 3 pods for app2, 1 for app1, 1 for app3
sudo kubectl get ingress         # 3 rules
```

Test the routing by `Host` header:

```bash
curl -H "Host: app1.com" http://192.168.56.110      # -> app1
curl -H "Host: app2.com" http://192.168.56.110      # -> app2
curl http://192.168.56.110                          # -> app3 (no Host header)
curl -H "Host: unknown.com" http://192.168.56.110   # -> app3 (default rule)
```

Prove the load balancing on app2. The pod name should change between requests:

```bash
for i in $(seq 1 6); do curl -s -H "Host: app2.com" http://192.168.56.110; done
```

### 🧹 Cleanup

```bash
vagrant destroy -f
```

## Inception of Things - Part 3: K3d, Docker and Argo CD

Part 3 introduces a local Kubernetes development workflow based on **Docker**, **k3d** and **Argo CD**. The cluster runs inside Docker containers, while Argo CD continuously reconciles the Kubernetes manifests stored in this Git repository. The application is therefore deployed through GitOps rather than by manually applying manifests after every change.

### 🏗️ Architecture & Specifications

- **Runtime:** Docker Engine and containerd.
- **Kubernetes distribution:** k3d, which runs k3s nodes as Docker containers.
- **Cluster:** `iot-cluster`.
- **Published port:** host port `8888` is forwarded to port `80` of the k3d load balancer.
- **GitOps controller:** Argo CD installed in the `argocd` namespace.
- **Application namespace:** `dev`.
- **Application port:** the container listens on port `8888`.
- **Public image:** `nmartindock/iot-app:v1`.

### 🔄 GitOps Workflow

The deployment follows this flow:

1. The setup script installs Docker, k3d and `kubectl`.
2. A k3d cluster named `iot-cluster` is created, with host port `8888` mapped to the cluster load balancer's HTTP port `80`.
3. The `argocd` and `dev` namespaces are created.
4. Argo CD is installed in the `argocd` namespace.
5. The Argo CD `Application` resource points to this repository and to the `p3/confs` directory.
6. Argo CD applies the Kubernetes manifests to the `dev` namespace and continuously monitors the Git repository.
7. Changes committed to the repository are automatically synchronized. With `prune` and `selfHeal` enabled, resources removed from Git are deleted from the cluster and manual drift is corrected.

### 🧩 Application Components

The sample application is a minimal Python HTTP server returning JSON on port `8888`. It is packaged as a small Alpine-based Docker image and runs as a non-root user.

The Kubernetes deployment contains:

| Resource | Name | Purpose |
|---|---|---|
| Deployment | `iot-app-deployment` | Runs one `iot-app` pod in the `dev` namespace. |
| Service | `iot-app-service` | Exposes the pod internally on port `8888`. |
| Ingress | `iot-app-ingress` | Routes HTTP requests on `/` to the service. |
| Argo CD Application | `iot-app-sync` | Synchronizes `p3/confs` with the cluster. |

### 📂 Project Structure

```text
p3/
├── confs/
│   ├── argocd-app.yaml       # Argo CD Application and automated sync policy
│   └── deployment.yaml       # Deployment, Service and Ingress for iot-app
└── scripts/
    ├── setup.sh              # Installs dependencies, creates k3d and installs Argo CD
    └── iot-app/
        ├── Dockerfile        # Builds the application image as a non-root user
        └── server.py         # Minimal Python JSON HTTP server
```

### 🚀 How to Run

From the repository root, execute the setup script with the privileges required to install Docker and Kubernetes tooling:

```bash
cd p3
sudo bash scripts/setup.sh
```

The script installs the required tools, creates the k3d cluster and installs Argo CD. Once the cluster is ready, apply the Argo CD `Application` resource:

```bash
kubectl apply -f p3/confs/argocd-app.yaml
```

The Argo CD controller then reads the manifests from `p3/confs` and deploys the application into the `dev` namespace.

> **Note:** Build and publish the application image before deployment if `nmartindock/iot-app:v1` is not already available in the registry:
>
> ```bash
> cd p3/scripts/iot-app
> docker build -t nmartindock/iot-app:v1 .
> docker push nmartindock/iot-app:v1
> ```

### ✅ Verification

Check the cluster and Argo CD resources:

```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -n argocd
kubectl get application -n argocd
kubectl get all -n dev
kubectl get ingress -n dev
```

Check the synchronization state and application health:

```bash
kubectl get application iot-app-sync -n argocd \
  -o jsonpath='{.status.sync.status}{"\n"}{.status.health.status}{"\n"}'
```

The expected result is a synchronized and healthy application, typically `Synced` and `Healthy` once Argo CD has completed reconciliation.

Test the application through the k3d load balancer:

```bash
curl http://localhost:8888
```

The endpoint should return a JSON response similar to:

```json
{"status": "ok", "message": "v1"}
```

To observe GitOps reconciliation, change a manifest or the application image tag, commit and push the change, then inspect Argo CD:

```bash
kubectl describe application iot-app-sync -n argocd
kubectl get pods -n dev -w
```

### 🧹 Cleanup

Delete the Argo CD application and the k3d cluster when the exercise is complete:

```bash
kubectl delete -f p3/confs/argocd-app.yaml
k3d cluster delete iot-cluster
```
