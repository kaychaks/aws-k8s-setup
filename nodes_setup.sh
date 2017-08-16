#!/usr/bin/env bash

echo "[deployment] Necessary software installations...initiating"

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update

apt-get install -y apt-transport-https ca-certificates curl software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update

apt-get install -y docker-ce

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"

chmod +x ./kubectl

mv ./kubectl /usr/local/bin/kubectl

apt-get install -y kubelet kubeadm

echo "[deployment] Necessary software installations....done"


## Join nodes with master
echo "[deployment] Joining node with master ${masterIP} ....initiating"

for i in {1..50}; do kubeadm join --token=${k8stoken} ${masterIP}:6443 && break || sleep 15; done

echo "[deployment] Joining node with master ${masterIP} ....done"
echo "[deployment] Node setup tasks complete."