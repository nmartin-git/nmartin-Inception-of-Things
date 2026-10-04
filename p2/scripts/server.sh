#!/bin/bash
set -e

export INSTALL_K3S_EXEC="server \
  --node-ip=192.168.56.110 \
  --bind-address=192.168.56.110 \
  --advertise-address=192.168.56.110 \
  --tls-san=192.168.56.110"

curl -sfL https://get.k3s.io | sh -

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
echo "export KUBECONFIG=/home/vagrant/.kube/config" >> /home/vagrant/.bashrc

until kubectl get nodes 2>/dev/null | grep -q " Ready "; do
  sleep 3
done

kubectl apply -f /vagrant_confs/