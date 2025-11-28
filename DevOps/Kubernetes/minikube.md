# Install Minikube on Debian 13 (with sudo)

## Prerequisites
- Debian 13 VM with sudo access
- Recommended: 2+ CPUs, 4 GB+ RAM, 20 GB disk
- Virtualization enabled (nested virtualization if VM is itself a guest)

## 1 — Update system
```bash
sudo apt update && sudo apt upgrade -y
```

## 2 — Install prerequisites
```bash
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release conntrack socat ebtables
```

## 3 — Install Docker (recommended driver)
```bash
# Add Docker GPG key and repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable and start Docker
sudo systemctl enable --now docker

# Allow non-root docker usage
sudo usermod -aG docker $USER

# IMPORTANT: Apply group membership by logging out and back in, or run:
newgrp docker

# Verify Docker works without sudo
docker run hello-world
```

**Note:** If the Docker verification fails, you must log out and log back in for the group membership to take effect. Do not proceed until `docker run hello-world` works without sudo.

## 4 — Install kubectl (required for verification)
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
rm kubectl
```

## 5 — Install Minikube binary
```bash
curl -Lo minikube-linux-amd64 https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version
rm minikube-linux-amd64
```

## 6 — Start Minikube (docker driver)
Ensure Docker works without sudo (Step 3 verification passed), then start Minikube:
```bash
minikube start --driver=docker --cpus=2 --memory=4096 --disk-size=20g
```

**Important:** Do not run Minikube with sudo, as it will create permission issues. If you get Docker permission errors, return to Step 3 and ensure the Docker group membership is properly applied.

## 7 — Verify cluster
```bash
minikube status
kubectl get nodes
kubectl get pods -A
```

## Useful commands
```bash
minikube dashboard       # opens dashboard; use --url on headless systems
minikube stop
minikube delete
minikube logs
kubectl config use-context minikube
```

## Troubleshooting notes
- **Docker permission denied**: If you see "permission denied" errors when running Docker or Minikube, your Docker group membership hasn't been applied. Log out and back in, or run `newgrp docker` in your current shell.
- **cgroup errors**: Ensure container runtime and host use compatible cgroup settings (systemd cgroup is preferred). Adjust container runtime or pass Minikube flags such as `--container-runtime=containerd` if needed.
- **Minikube won't start**: Do not run Minikube with sudo. Ensure `docker run hello-world` works without sudo first.
- On headless VMs without nested virtualization or unsupported hypervisors, the Docker driver is typically the most reliable.
- If `minikube start` fails, inspect `minikube logs` and `journalctl -u docker` for details.
