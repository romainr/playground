#!/bin/bash
# Copyright 2020 The SQLFlow Authors. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

echo -e "
\033[32m
This script is safe to re-run, feel free to retry when it exits abnormally.
Especially when we are waiting for a pod in Kubernetes cluster, it may
pull image from registry and take a lot of time to startup.
\033[0m
"

if [[ "$(whoami)" != "root" ]]; then
    echo "Please change to root user and retry."
    exit 1
fi

# script base dir for starting the minikube cluster
filebase=/root/scripts

echo "Docker pull dependency images, you can comment this if already have them ..."
if [[ -d "/root/.sqlflow" ]]; then
    echo "Cache found at /root/.sqlflow ..."
    if [[ ! -f "/root/.sqlflow/.loaded" ]]; then
        find /root/.sqlflow/* | xargs -I'{}' sh -c "docker load -i '{}' && sleep 10"
        touch /root/.sqlflow/.loaded
    fi
    # use local step images for model zoo model
    docker tag sqlflow/sqlflow:step sqlflow/sqlflow:latest
else
    # c.f. https://github.com/sql-machine-learning/sqlflow/blob/develop/.travis.yml
    docker pull sqlflow/sqlflow:jupyter
    docker pull sqlflow/sqlflow:mysql
    docker pull sqlflow/sqlflow:server
    docker pull sqlflow/sqlflow:step
    docker pull sqlflow/sqlflow:modelzooserver
    docker pull argoproj/argoexec:v2.7.7
    docker pull argoproj/argocli:v2.7.7
    docker pull argoproj/workflow-controller:v2.7.7
    docker tag sqlflow/sqlflow:modelzooserver sqlflow/sqlflow:model_zoo
fi
echo "Done."

# NOTE: According to https://stackoverflow.com/a/16619261/724872,
# source is very necessary here.
source $filebase/export_k8s_vars.sh
source $filebase/find_fastest_resources.sh

# (FIXME:lhw) If grep match nothing and return 1, do not exit
# Find a way that we do not need to use 'set -e'
set +e

# Execute cmd until given output is present
# or exit when timeout (50*3s)
# "$1" is user message
# "$2" is cmd
# "$3" is expected output
function wait_or_exit() {
    echo -n "Waiting for $1 "
    for i in {1..50}; do
        $2 | grep -o -q "$3"
        if [[ $? -eq 0 ]]; then
            echo "Done"
            return
        fi
        echo -n "."
        sleep 3
    done
    echo "Fail"
    exit
}

# Use a faster kube image and docker registry
echo "Start minikube cluster ..."
minikube_status=$(minikube status | grep "apiserver: Running")
if [[ "$minikube_status" == "apiserver: Running" ]]; then
  echo "Already in running."
else
    ali_kube="http://kubernetes.oss-cn-hangzhou.aliyuncs.com"
    google_kube="http://k8s.gcr.io"
    fast_kube_site=$(find_fastest_url $ali_kube $google_kube)
    if [[ "$fast_kube_site" == "$ali_kube" ]]; then
        sudo minikube start --image-mirror-country cn \
          --registry-mirror=https://registry.docker-cn.com --driver=none \
          --kubernetes-version=v"$K8S_VERSION"
    else
        sudo minikube start \
          --vm-driver=none \
          --kubernetes-version=v"$K8S_VERSION"
    fi
fi

wait_or_exit "minikube" "minikube status" "apiserver: Running"

# Test if a Kubernetes pod is ready
# "$1" shoulde be namespace id e.g. argo
# "$2" should be pod selector e.g. k8s-app=kubernetes-dashboard
function is_pod_ready() {
    pod=$(kubectl get pod -n "$1" -l "$2" -o name | tail -1)
    if [[ -z "$pod" ]]; then
        echo "no"
        return
    fi
    ready=$(kubectl get -n "$1" "$pod" -o jsonpath='{.status.containerStatuses[0].ready}')
    if [[ "$ready" == "true" ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

echo "Start argo ..."
argo_server_alive=$(is_pod_ready "argo" "app=argo-server")
if [[ "$argo_server_alive" == "yes" ]]; then
    echo "Already in running."
else
    $filebase/start_argo.sh
fi
wait_or_exit "argo" "is_pod_ready argo app=argo-server" "yes"

echo "Strat Kubernetes Dashboard ..."
dashboard_alive=$(is_pod_ready "kubernetes-dashboard" "k8s-app=kubernetes-dashboard")
if [[ "$dashboard_alive" == "yes" ]]; then
    echo "Already in running."
else
    nohup minikube dashboard >/dev/null 2>&1 &
fi
wait_or_exit "Kubernetes Dashboard" "is_pod_ready kubernetes-dashboard k8s-app=kubernetes-dashboard" "yes"

echo "Strat SQLFlow ..."
sqlflow_alive=$(is_pod_ready "default" "app=sqlflow-server")
if [[ "$sqlflow_alive" == "yes" ]]; then
    echo "Already in running."
else
    kubectl apply -f $filebase/install-sqlflow.yaml
fi
wait_or_exit "SQLFlow" "is_pod_ready default app=sqlflow-server" "yes"

# Kill port exposing if it already exist
function stop_expose() {
    ps -elf | grep "kubectl port-forward" | grep "$1" | grep "$2" | awk '{print $4}' | xargs kill  >/dev/null 2>&1
}

# Kubernetes port-forwarding
# "$1" should be namespace
# "$2" should be resource, e.g. service/argo-server
# "$3" should be port mapping, e.g. 8000:80
function expose() {
    stop_expose "$2" "$3"
    echo "Exposing port for $2 at $3 ..."
    nohup kubectl port-forward -n $1 --address='0.0.0.0' $2 $3 >>port-forward-log 2>&1 &
}

# (NOTE) after re-deploy sqlflow we have to re-expose the service ports.
expose kubernetes-dashboard service/kubernetes-dashboard 9000:80
expose argo service/argo-server 9001:2746
expose default pod/sqlflow-server 8888:8888
expose default pod/sqlflow-server 3306:3306
expose default pod/sqlflow-server 50051:50051
expose default pod/sqlflow-server 50055:50055

# Get Jupyter Notebook's token, for single-user mode, we disabled the token checking
# jupyter_addr=$(kubectl logs pod/sqlflow-server notebook | grep -o -E "http://127.0.0.1[^?]+\?token=.*" | head -1)
mysql_addr="mysql://root:root@tcp($(kubectl get -o jsonpath='{.status.podIP}' pod/sqlflow-server))/?maxAllowedPacket=0"

echo -e "
\033[32m
Congratulations, SQLFlow playground is up!

Access Jupyter Notebook at: http://localhost:8888
Access Kubernetes Dashboard at: http://localhost:9000
Access Argo Dashboard at: http://localhost:9001
Access SQLFlow with cli: ./sqlflow --data-source="\"$mysql_addr\""
Access SQLFlow Model Zoo at: localhost:50055

Stop minikube with: minikube stop
Stop vagrant vm with: vagrant halt

[Dangerous]
Destroy minikube with: minikube delete && rm -rf ~/.minikube
Destroy vagrant vm with: vagrant destroy
\033[0m
"
