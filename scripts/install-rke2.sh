#!/bin/bash

# Kubernetes Installation Script for Rancher Nodes
# This script installs RKE2 on Proxmox VMs

set -e

KUBE_VERSION="${1:-v1.27.6}"
RANCHER_ROLE="${2:-server}"  # server or agent

echo "Installing Kubernetes RKE2..."
echo "Version: $KUBE_VERSION"
echo "Role: $RANCHER_ROLE"

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install dependencies
sudo apt-get install -y \
    curl \
    wget \
    git \
    vim \
    net-tools \
    htop \
    ntp

# Install qemu-guest-agent
sudo apt-get install -y qemu-guest-agent
sudo systemctl start qemu-guest-agent
sudo systemctl enable qemu-guest-agent

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Install RKE2
if [ "$RANCHER_ROLE" = "server" ]; then
    echo "Installing RKE2 server..."
    curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=$KUBE_VERSION sh -
    
    sudo systemctl start rke2-server
    sudo systemctl enable rke2-server
    
    # Wait for server to be ready
    echo "Waiting for RKE2 server to start..."
    sleep 30
    
    # Copy kubeconfig
    mkdir -p ~/.kube
    sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
    sudo chown $USER:$USER ~/.kube/config
    chmod 600 ~/.kube/config
    
    # Update server IP
    INTERNAL_IP=$(hostname -I | awk '{print $1}')
    sed -i "s/127.0.0.1/$INTERNAL_IP/g" ~/.kube/config
    
    echo "RKE2 server installed successfully"
    echo "Kubeconfig: ~/.kube/config"
    
else
    echo "Installing RKE2 agent..."
    
    read -p "Enter server URL (e.g., https://192.168.1.100:6443): " SERVER_URL
    read -s -p "Enter server token: " SERVER_TOKEN
    echo ""
    
    curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=$KUBE_VERSION INSTALL_RKE2_TYPE=agent sh -
    
    sudo mkdir -p /etc/rancher/rke2/
    
    sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
server: $SERVER_URL
token: $SERVER_TOKEN
EOF
    
    sudo systemctl start rke2-agent
    sudo systemctl enable rke2-agent
    
    echo "RKE2 agent installed successfully"
fi

# Add RKE2 to PATH
echo "export PATH=/opt/rke2/bin:\$PATH" >> ~/.bashrc
source ~/.bashrc

echo "Installation complete!"
