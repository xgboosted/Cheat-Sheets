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

# Allow non-root docker usage (you must log out and back in or run `newgrp docker`)
sudo usermod -aG docker $USER
```

## 4 — (Optional) Install kubectl
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

## 5 — Install Minikube binary
```bash
curl -Lo minikube-linux-amd64 https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
```

## 6 — Start Minikube (docker driver)
If you added your user to the `docker` group and re-logged in:
```bash
minikube start --driver=docker --cpus=2 --memory=4096 --disk-size=20g
```
Otherwise run with sudo:
```bash
sudo minikube start --driver=docker --cpus=2 --memory=4096 --disk-size=20g
```

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
- cgroup errors: ensure container runtime and host use compatible cgroup settings (systemd cgroup is preferred). Adjust container runtime or pass Minikube flags such as `--container-runtime=containerd` if needed.
- After adding your user to the `docker` group, log out and back in or run `newgrp docker` to apply the group change.
- On headless VMs without nested virtualization or unsupported hypervisors, the Docker driver is typically the most reliable.
- If `minikube start` fails, inspect `minikube logs` and `journalctl -u docker` for details.
