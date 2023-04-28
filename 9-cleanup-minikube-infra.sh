#!/usr/bin/env bash

#check pre-requisities: TODO check version
command -v minikube  >/dev/null 2>&1 || { log::error >&2 "can't find minikube.  Aborting."; exit 1; }



for c in $(minikube profile list -o json | jq -r .valid[].Name);
do minikube delete -p $c;
done


rm -fr *.xml kubeconfig
