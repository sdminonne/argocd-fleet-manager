#!/usr/bin/env bash
ROOTDIR=$(git rev-parse --show-toplevel)

. ${ROOTDIR}/common.sh

#check pre-requisities: TODO check version
command -v minikube  >/dev/null 2>&1 || { log::error >&2 "can't find minikube.  Aborting."; exit 1; }


log::info "Cleaning /etc/hosts"
for c in $(minikube profile list -o json | jq -r .valid[].Name);
do sudo sed  -i "/$(minikube -p $c ip) ${c}/d"  /etc/hosts;
done
sudo sed  -i "/$(minikube -p ${MGMT} ip) my-git.io/d" /etc/hosts;

for c in $(minikube profile list -o json | jq -r .valid[].Name);
do minikube delete -p $c;
done

rm -fr *.xml kubeconfig
