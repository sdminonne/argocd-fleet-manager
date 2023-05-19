#!/usr/bin/env bash


. common.sh

log::info "KUBECONFIG $KUBECONFIG"

#check pre-requisities: TODO check version
command -v kubectl >/dev/null 2>&1 || { log::error >&2 "can't find kubectl.  Aborting."; exit 1; }

#check pre-requisities: TODO check version
command -v minikube  >/dev/null 2>&1 || { log::error >&2 "can't find minikube.  Aborting."; exit 1; }

minikube_up_and_running() {
    local profile=$1
    apiStatus=$(minikube -p $profile status --format='{{ .APIServer }}')
  hostStatus=$(minikube -p $profile status --format='{{ .Host }}')
  if [[ "${apiStatus}" == "Running" && "${hostStatus}" == "Running" ]]
  then
    echo "0"
    return
  fi
  echo "1"
}


minikube_stopped() {
  local profile=$1
  apiStatus=$(minikube -p $profile status --format='{{ .APIServer }}')
  hostStatus=$(minikube -p $profile status --format='{{ .Host }}')
  if [[ "${apiStatus}" == "Stopped" && "${hostStatus}" == "Stopped" ]]
  then
    echo "0"
    return
  fi
  echo "1"
}


net_active() {
    local netname=$1
    active=$(virsh net-info $netname  | awk '/Active:/ {print $2}')
    if [[ "${active}" == "yes" ]]
    then
      echo "0"
      return
    fi
    echo "1"
}

containerRuntime=$(minikube config get container-runtime )
[[ "${containerRuntime}" == "cri-o" ]] || { log::error >&2 "Container runtime should be cri-o"; exit 1; }

driver=$(minikube config get driver )
[[ "${driver}" == "kvm2" ]] || { log::error >&2 "Driver should be kvm2. While it looks ${driver}"; exit 1; }


for CLUSTERNAME in "${clusters[@]}"
do
   echo "Setting up clustername ${CLUSTERNAME}";
   minikube start -p ${CLUSTERNAME};
   wait_until "minikube_up_and_running ${CLUSTERNAME}";
#   [ "${CLUSTERNAME}" == "${MGMT}" ] && { minikube -p "${CLUSTERNAME}" addons enable ingress; };
done


log::info "Stopping minikube(s)"
for CLUSTERNAME in "${clusters[@]}"
do
  virsh net-dumpxml mk-${CLUSTERNAME}  > mk-${CLUSTERNAME}.xml;
  minikube stop -p ${CLUSTERNAME};
  wait_until "minikube_stopped ${CLUSTERNAME}"
  virsh net-destroy mk-${CLUSTERNAME};
done

for CLUSTERNAME in "${clusters[@]}"
do
   log::info "Setting  mk-${CLUSTERNAME} in mode='route'"
   sed -i "/uuid/a \  <forward mode='route'/\>" mk-${CLUSTERNAME}.xml;
   virsh net-define mk-${CLUSTERNAME}.xml;
   virsh net-start mk-${CLUSTERNAME};
   wait_until "net_active mk-${CLUSTERNAME}";
done

log::info "Restaring minikube(s)"
for CLUSTERNAME in "${clusters[@]}"
do
   minikube start -p ${CLUSTERNAME};
   wait_until "minikube_up_and_running ${CLUSTERNAME}"
done


exit
