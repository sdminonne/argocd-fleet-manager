#!/usr/bin/env bash

MGMT=mgmt

#declare -a managedclusters=("cluster1" "cluster2")
declare -a managedclusters=("cluster1")

declare -a clusters=("${MGMT}" "${managedclusters[@]}")

#Log in RED
log::error() {
  printf "\033[0;31m%s\033[0m\n" "ERROR: $1"
}

#Log in yellow
log::warning() {
  printf "\033[1;33m%s\033[0m\n" "WARNING: $1"
}

#Log in green
log::info() {
  printf "\033[0;32m%s\033[0m\n" "INFO: $1"
}


get_client_context_from_cluster_name()  {
    local clustername=$1
     case $(uname -s) in
	'Linux') # Here we assume on Linux we always use minikube
	    echo ${clustername}
	    ;;
	'kind')  # Otherwise kind :(
	    echo kind-${clustername}
	    ;;
    esac
}


wait_until() {
  local script=$1
  local wait=${2:-.5}
  local timeout=${3:-10}
  local i

  script_pretty_name=$(echo "$script" | sed 's/_/ /g')
  times=$(echo "($(bc <<< "scale=2;$timeout/$wait")+0.5)/1" | bc)
  for i in $(seq 1 "$times"); do
    local out=$($script)
    if [ "$out" == "0" ]
    then
      log::info "${script_pretty_name}: OK"
      return 0
    fi
    log::warning "${script_pretty_name}: Waiting... Timeout in $((timeout-(i*wait))) seconds"
    sleep $wait
  done
  log::error "${script_pretty_name}"
  return 1
}

pod_in_namespace_for_context_is_running() {
    local context=$3
    local namespace=$2
    local pod=$1
    podstatus=$(kubectl --context $context -n ${namespace} get pod ${pod} -o jsonpath='{.status.phase}')
    if [[ "${podstatus}" == "Running" ]]
    then
        echo "0"
        return
    fi
    echo "1"
}



all_pods_in_namespace_for_context_are_running() {
    local context=$2
    local namespace=$1
    podsNotRunning=$(kubectl --context ${context} get pods -n ${namespace} -o jsonpath='{.items[?(@.status.phase!="Running")].metadata.name}')
    [ -z "$podsNotRunning" ] && { echo "0" ; return; }
    echo "1"
}

deployment_in_namespace_for_context_up_and_running() {
    kubecontext=$3
    namespace=$2
    deployment=$1


    rv="1"
    zero=0
    #TODO troubleshoot --ignore-not-found
    desiredReplicas=$(kubectl --context ${kubecontext}  get deployment ${deployment} -n ${namespace} -ojsonpath="{.spec.replicas}" --ignore-not-found)
    readyReplicas=$(kubectl --context ${kubecontext}  get deployment ${deployment} -n ${namespace} -ojsonpath="{.status.readyReplicas}" --ignore-not-found)
    if [ "${desiredReplicas}" == "${readyReplicas}" ] && [ "${desiredReplicas}" != "${zero}" ]; then
	    rv="0"
    fi

    echo ${rv}
}


https_endpoint_is_up()  {
  httpendpoint=$1
  httpstatus=$(curl -I  ${httpendpoint} 2>/dev/null | head -n 1 | cut -d$' ' -f2)
  if [[ "${httpstatus}" == "200" ]]
  then
    echo "0"
    return
  fi
  echo "1"
}


https_insecure_endpoint_is_up()  {
  httpendpoint=$1
  httpstatus=$(curl -I  -k ${httpendpoint} 2>/dev/null | head -n 1 | cut -d$' ' -f2)
  if [[ "${httpstatus}" == "200" ]]
  then
    echo "0"
    return
  fi
  echo "1"
}

crd_defined_for_context() {
    crd=$1
    context=$2
    kubectl --context ${context} get crd ${crd} &>/dev/null
    if [[ $? -ne 0 ]]
    then
        echo "1"
    else
        echo "0"
    fi
    return
}
