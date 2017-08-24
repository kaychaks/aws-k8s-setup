#!/usr/bin/env bash

echo "[deployment] Necessary software installations...initiating"

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update

apt-get install -y apt-transport-https ca-certificates curl software-properties-common ceph-fs-common ceph-common jq

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

## creating cluster now

echo "[deployment] kubeadm cluster creation....initiating"
kubeadm init --token=${k8s_token}

mkdir /home/ubuntu/.kube
chown ubuntu:ubuntu /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

echo "[deployment] kubeadm cluster creation....done"

echo "[deployment] cluster networking setup....initiating"
for i in {1..50}; do
    kubever=$(sudo -u ubuntu -H kubectl version | base64 | tr -d '\n')
    sudo -u ubuntu -H kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$kubever" && break || sleep 15
done
echo "[deployment] cluster networking setup....done"

# let master and all nodes get READY
echo "[deployment] waiting for all nodes to get READY...."

ready_status=$(sudo -u ubuntu -H kubectl get no -o json | jq '[.items[] | .status.conditions | map(select(.type == "Ready").status)] | flatten | all')

until [ "$ready_status" = true ]; do
    echo "[deployment] ..."
    ready_status=$(sudo -u ubuntu -H kubectl get no -o json | jq '[.items[] | .status.conditions | map(select(.type == "Ready").status)] | flatten | all')
done

echo "[deployment] waiting for all nodes to get READY....done"

echo "[deployment] setting up Helm"

sudo -u ubuntu -H mkdir /home/ubuntu/helm-dl
cd /home/ubuntu

sudo -u ubuntu -H wget https://storage.googleapis.com/kubernetes-helm/helm-v2.6.0-linux-amd64.tar.gz
sudo -u ubuntu -H tar -zx -C /home/ubuntu/helm-dl -xzf helm-v2.6.0-linux-amd64.tar.gz
find /home/ubuntu/helm-dl -name helm -type f -exec /bin/mv {} /usr/local/bin \;

echo "${helm_yml}" | sudo -u ubuntu -H tee /home/ubuntu/helm_rbac.yml
sudo -u ubuntu -H kubectl create -f /home/ubuntu/helm_rbac.yml
sudo -u ubuntu -H /usr/local/bin/helm init --service-account helm

rm -rf /home/ubuntu/helm-dl /home/ubuntu/*.tar.gz

echo "[deployment] setting up Helm....done"


echo "[deployment] cluster deployment tasks complete."
