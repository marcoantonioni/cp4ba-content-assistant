#!/bin/bash

#set -euo pipefail

_me=$(basename "$0")

_CFG=""
_CMD=""
_FORCE=false
_IS_DYNAMIC_PACKAGE=0

#--------------------------------------------------------
_CLR_RED="\033[0;31m"   #'0;31' is Red's ANSI color code
_CLR_GREEN="\033[0;32m"   #'0;32' is Green's ANSI color code
_CLR_YELLOW="\033[1;33m"   #'1;32' is Yellow's ANSI color code
_CLR_BLUE="\033[0;34m"   #'0;34' is Blue's ANSI color code
_CLR_NC="\033[0m"

#--------------------------------------------------------
_INST_TMP_FOLDER="/tmp"
setTemporaryFolder () {
  _OK=0
  _ERR_MSG_FOLDER="is a folder"
  _ERR_MSG_PERMISSIONS=""
  if [[ ! -z "${CP4BA_INST_TMP_FOLDER}" ]]; then
    if [[ -d "${CP4BA_INST_TMP_FOLDER}" ]]; then
      if [[ -r "${CP4BA_INST_TMP_FOLDER}" ]] && [[ -w "${CP4BA_INST_TMP_FOLDER}" ]]; then 
        _OK=1
      else
        _ERR_MSG_PERMISSIONS=", you have not rights to read and/or write"
        _OK=-1
      fi
    else
      _ERR_MSG_FOLDER="is NOT a folder"
    fi

    if [[ $_OK -lt 1 ]]; then
      echo -e "${_CLR_RED}[✗] ERROR '${_CLR_YELLOW}${CP4BA_INST_TMP_FOLDER}${_CLR_RED}' is not a valid temporary folder, check if it is a folder or if you have write permissions !${_CLR_NC}"
      echo -e "${_CLR_RED} '${_CLR_YELLOW}${CP4BA_INST_TMP_FOLDER}${_CLR_RED}' ${_ERR_MSG_FOLDER}${_ERR_MSG_PERMISSIONS}${_CLR_NC}"
      exit 1
    fi
    export _INST_TMP_FOLDER="${CP4BA_INST_TMP_FOLDER}"
  fi
  log_info "${_CLR_GREEN}Running with temporary folder '${_CLR_YELLOW}${_INST_TMP_FOLDER}${_CLR_GREEN}'${_CLR_NC}"

}

#--------------------------------------------------------
# read command line params
while getopts c:k:f flag
do
    case "${flag}" in
        c) _CFG=${OPTARG};;
        k) _CMD=${OPTARG};;
        f) _FORCE=true;;
    esac
done

usage() {
  echo "usage: $_me -c path-of-config-file -k [install|remove]"
}

if [[ -z "${_CFG}" ]]; then
  usage 
  exit 1
fi

source "${_CFG}" 2>/dev/null 1>/dev/null

#----------------------------------------------------
_SCRIPT_PATH="${BASH_SOURCE}"
while [ -L "${_SCRIPT_PATH}" ]; do
  _SCRIPT_DIR="$(cd -P "$(dirname "${_SCRIPT_PATH}")" >/dev/null 2>&1 && pwd)"
  _SCRIPT_PATH="$(readlink "${_SCRIPT_PATH}")"
  [[ ${_SCRIPT_PATH} != /* ]] && _SCRIPT_PATH="${_SCRIPT_DIR}/${_SCRIPT_PATH}"
done
_SCRIPT_PATH="$(readlink -f "${_SCRIPT_PATH}")"
_SCRIPT_DIR="$(cd -P "$(dirname -- "${_SCRIPT_PATH}")" >/dev/null 2>&1 && pwd)"

#----------------------------------------------------
if [[ ! -f "$_SCRIPT_DIR/../../cp4ba-logger/scripts/logger.sh" ]]; then
  echo "Error, log package not found !"
  echo "Clone it alongside with other cp4ba-..."
  echo "use the command: git clone https://github.com/marcoantonioni/cp4ba-logger"
  exit 1
fi
source $_SCRIPT_DIR/../../cp4ba-logger/scripts/logger.sh
if [[ -z "${CP4BA_LOGGING_ENABLED}" ]]; then 
  export CP4BA_LOGGING_ENABLED=true
fi
if [[ -z "${CP4BA_LOG_LEVEL}" ]]; then 
  export CP4BA_LOG_LEVEL="INFO"
fi
if [[ -z "${CP4BA_LOG_TO_CONSOLE}" ]]; then 
  export CP4BA_LOG_TO_CONSOLE=true
fi
if [[ -z "${CP4BA_LOG_TO_FILE}" ]]; then 
  export CP4BA_LOG_TO_FILE=false
fi
if [[ -z "${CP4BA_LOG_FILE}" ]]; then 
  export CP4BA_LOG_FILE=""
fi
if [[ -z "${CP4BA_LOG_MAX_SIZE}" ]]; then 
  export CP4BA_LOG_MAX_SIZE=$((10 * 1024 * 1024))
fi
if [[ -z "${CP4BA_LOG_BACKUP_COUNT}" ]]; then 
  export CP4BA_LOG_BACKUP_COUNT=5
fi

#-------------------------------
resourceExist () {
#    echo "namespace name: $1"
#    echo "resource type: $2"
#    echo "resource name: $3"
  if [ $(oc get $2 -n $1 $3 2> /dev/null | grep $3 2>/dev/null | wc -l) -lt 1 ];
  then
      return 0
  fi
  return 1
}


#-----------------------------------------------------------------
createCACMSSecrets() {
  log_info "Create CACMS secrets"

  #----------------
  oc delete secret -n ${CP4BA_INST_NAMESPACE} "${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME}-vector-db-creds" 2> /dev/null 1> /dev/null

  oc create secret generic -n ${CP4BA_INST_NAMESPACE} "${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME}-vector-db-creds" \
    --from-literal=VECTOR_DATABASE_USER_ID="genai-service-user" \
    --from-literal=VECTOR_DATABASE_USER_PASSWORD="${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_ADMIN_PASSWORD}" 2>/dev/null 1>/dev/null

  oc label secret -n ${CP4BA_INST_NAMESPACE} "${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME}-vector-db-creds" cas.ibm.com/backup-type=mandatory 2> /dev/null 1> /dev/null

  #----------------
  oc delete secret -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-secret 2> /dev/null 1> /dev/null

  oc create secret generic -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-secret \
    --from-literal=AI_PROVIDER_API_KEY_WATSONXPROD="${CP4BA_INST_CACMS_AIPROVIDER_API_KEY}" \
    --from-literal=AI_PROVIDER_SPACE_ID_WATSONXPROD="${CP4BA_INST_CACMS_AIPROVIDER_SPACE_ID}" 2>/dev/null 1>/dev/null

  oc label secret -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-secret cas.ibm.com/backup-type=mandatory 2> /dev/null 1> /dev/null

  #----------------
  oc delete secret -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-admin-key-secret 2> /dev/null 1> /dev/null

  oc create secret generic -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-admin-key-secret \
    --from-literal=ACCESS_TOKEN_KEY_PASSPHRASE="${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_ADMIN_PASSWORD}" \
    --from-literal=admin_key.pem="${CP4BA_INST_CACMS_AIPROVIDER_SPACE_ID}" 2>/dev/null 1>/dev/null

  oc label secret -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-admin-key-secret cas.ibm.com/backup-type=mandatory 2> /dev/null 1> /dev/null

}

#-----------------------------------------------------------------
createCACMSCluster() {
  log_info "Create CACMS cluster"

  #----------------
  oc delete casclusters.cas.ibm.com -n ${CP4BA_INST_NAMESPACE} ${CP4BA_INST_CACMS_CAS_CR_NAME} 2> /dev/null 1> /dev/null

if [[ -z "${CP4BA_INST_CACMS_CAS_SECRET_NAME}" ]]; then
  export CP4BA_INST_CACMS_CAS_SECRET_NAME="icp4a-root-ca"
fi

# https://www.ibm.com/docs/en/cacms/1.0.x?topic=reference-content-assistant-parameters
cat <<EOF | oc create -f - 2>/dev/null 1>/dev/null
apiVersion: cas.ibm.com/v1
kind: CASCluster
metadata:
  name: ${CP4BA_INST_CACMS_CAS_CR_NAME}
  namespace: ${CP4BA_INST_NAMESPACE}
  labels:
    app.kubernetes.io/instance: ibm-cas
    app.kubernetes.io/managed-by: ibm-cas
    app.kubernetes.io/name: ibm-cas
    release: ${CP4BA_INST_CACMS_CAS_APPVER}
spec:
  appVersion: ${CP4BA_INST_CACMS_CAS_APPVER}
  license:
    accept: true
  shared_configuration:
    image_pull_secrets:
      - ibm-entitlement-key
    root_ca_secret: ${CP4BA_INST_CACMS_CAS_SECRET_NAME}
    sc_cas_license_type: ${CP4BA_INST_CACMS_CAS_LICENSE_TYPE}
    sc_deployment_platform: ${CP4BA_INST_CACMS_CAS_DEPLOYMENT_PLATF}
    sc_deployment_profile_size: ${CP4BA_INST_CACMS_CAS_PROFILE_SIZE}
    sc_image_repository: cp.icr.io
    storage_configuration:
      sc_slow_file_storage_classname: ${CP4BA_INST_SC_FILE}
    trusted_certificate_list: [ '${CP4BA_INST_OPENSEARCH_CUSTOM_CERT_SECRET_NAME}' ]
  vector_database:
    vector_database_auth_type: BASICAUTH
    vector_database_certificate: "${CP4BA_INST_OPENSEARCH_CUSTOM_CERT_SECRET_NAME}"
    vector_database_secret_name: "${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME}-vector-db-creds"
    vector_database_ssl_enabled: true
    vector_database_type: opensearch
    vector_database_url: 'https://${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME}.${CP4BA_INST_NAMESPACE}.svc.cluster.local:9200'
EOF

}

waitCACMSClusterReady() {
  log_info "Wait for Content Assistant cluster readiness"

  while true;
  do
  _CAS_READY=$(oc get casclusters.cas.ibm.com -n ${CP4BA_INST_NAMESPACE} ${CP4BA_INST_CACMS_CAS_CR_NAME} -o jsonpath="{.status.conditions}" | jq '.[] | select(.type=="PostDeployCompleted").status' | sed 's/"//g')

    if [[ "${_CAS_READY}" = "True" ]]; then
      break
    else
      sleep 1  
    fi
  done

}

#-----------------------------------------------------------------
installCACMSOperator() {
  log_info "Create CACMS operator"

  #----------------
  oc create -f "${CP4BA_INST_CACMS_PACKAGE_FOLDER}/descriptors/content-assistant/cas_v1_cas_crd.yaml" 2>/dev/null 1>/dev/null
  oc create -f "${CP4BA_INST_CACMS_PACKAGE_FOLDER}/descriptors/content-assistant/rbac/service_account.yaml" 2>/dev/null 1>/dev/null
  oc create -f "${CP4BA_INST_CACMS_PACKAGE_FOLDER}/descriptors/content-assistant/rbac/role.yaml" 2>/dev/null 1>/dev/null
  oc create -f "${CP4BA_INST_CACMS_PACKAGE_FOLDER}/descriptors/content-assistant/rbac/role_binding.yaml" 2>/dev/null 1>/dev/null  
  oc create -f "${CP4BA_INST_CACMS_PACKAGE_FOLDER}/descriptors/content-assistant/op-olm/catalogsource.yaml" 2>/dev/null 1>/dev/null

  #----------------
  _OG_COUNT=$(oc get operatorgroups.operators.coreos.com -n ${CP4BA_INST_NAMESPACE} --no-headers | wc -l)
  if [[ $_OG_COUNT -eq 0 ]]; then
    cat "${CP4BA_INST_CACMS_PACKAGE_FOLDER}/descriptors/content-assistant/op-olm/operator_group.yaml" | sed 's/REPLACE_NAMESPACE/'${CP4BA_INST_NAMESPACE}'/g' | oc apply -f - 2>/dev/null 1>/dev/null
  fi

  #----------------
  cat "${CP4BA_INST_CACMS_PACKAGE_FOLDER}/descriptors/content-assistant/op-olm/subscription.yaml" | sed 's/REPLACE_NAMESPACE/'${CP4BA_INST_NAMESPACE}'/g' | oc apply -f - 2>/dev/null 1>/dev/null

  while true;
  do
    _CACMS_OPERATOR_POD=$(oc get pod -n ${CP4BA_INST_NAMESPACE} | grep ibm-content-assistant-operator | awk '{print $1}')
    if [[ ! -z "${_CACMS_OPERATOR_POD}" ]]; then
      _CACMS_OPERATOR_STATUS=$(oc get pod -n ${CP4BA_INST_NAMESPACE} ${_CACMS_OPERATOR_POD} -o jsonpath="{.status.phase}"  2>/dev/null)
      if [[ "${_CACMS_OPERATOR_STATUS}" = "Running" ]]; then
        break
      fi
    fi
  done

}

#-----------------------------------------------------------------
waitOpenSearchClusterReady() {
  log_info "Wait for OpenSearch cluster readiness"
  while true;
  do
    _OS_AVAILABLE=$(oc get clusters.opensearch.cloudpackopen.ibm.com -n ${CP4BA_INST_NAMESPACE} ${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME} --no-headers -o jsonpath="{.status.phase}" 2>/dev/null | sed 's/"//g')

    if [[ "${_OS_AVAILABLE}" = "Available" ]]; then
      break
    else
      sleep 1  
    fi
  done

  _NUM_POD_READY=0
  while [[ $_NUM_POD_READY -lt 3 ]]
  do
    sleep 1
    _NUM_POD_READY=$(oc get pod -n ${CP4BA_INST_NAMESPACE} | grep ${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME} | grep Running | wc -l)

  done

  _SERVICE=0
  while [[ $_SERVICE -lt 1 ]]
  do
    sleep 1
    _SERVICE=$(oc get svc ${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME} -n ${CP4BA_INST_NAMESPACE} --no-headers  2>/dev/null | wc -l)

  done

  while true;
  do
    _OS_CONDITIONS_AVAILABLE=$(oc get clusters.opensearch.cloudpackopen.ibm.com -n ${CP4BA_INST_NAMESPACE} ${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME} -o jsonpath="{.status.conditions}" 2>/dev/null  | jq '.[] | select(.type=="Available").status' | sed 's/"//g')

    if [[ "${_OS_CONDITIONS_AVAILABLE}" = "True" ]]; then
      break
    else
      sleep 1  
    fi
  done

}


#-----------------------------------------------------------------
cacmsRemoveResources() {
  oc delete casclusters.cas.ibm.com -n ${CP4BA_INST_NAMESPACE} ${CP4BA_INST_CACMS_CAS_CR_NAME} 2> /dev/null 1> /dev/null
  oc delete secret -n ${CP4BA_INST_NAMESPACE} "${CP4BA_INST_OPENSEARCH_CUSTOM_CLUSTER_NAME}-vector-db-creds" 2> /dev/null 1> /dev/null
  oc delete secret -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-secret 2> /dev/null 1> /dev/null
  oc delete secret -n ${CP4BA_INST_NAMESPACE} ibm-content-assistant-admin-key-secret 2> /dev/null 1> /dev/null
}

#-----------------------------------------------------------------
cacmsSetup() {
  installCACMSOperator
  createCACMSSecrets
  waitOpenSearchClusterReady
  sleep 5 # give security job time to complete
  createCACMSCluster
  waitCACMSClusterReady
}

downloadOrVerifyPackage() {
  if [[ ! -z "${CP4BA_INST_CACMS_PACKAGE_DYNAMIC_DOWNLOAD_VER}" ]]; then
    _OLOC=$(pwd)
    _TMP_PCKG_FOLDER="${_INST_TMP_FOLDER}/CACMS-$RANDOM"
    mkdir -p $_TMP_PCKG_FOLDER
    cd $_TMP_PCKG_FOLDER
    curl -sk -LO https://github.com/ibm-ecm/ibm-content-assistant-client-managed-software/archive/refs/heads/${CP4BA_INST_CACMS_PACKAGE_DYNAMIC_DOWNLOAD_VER}.zip 2>/dev/null 1>/dev/null 

    unzip ./${CP4BA_INST_CACMS_PACKAGE_DYNAMIC_DOWNLOAD_VER}.zip 2>/dev/null 1>/dev/null 

    _IS_DYNAMIC_PACKAGE=1
    export CP4BA_INST_CACMS_PACKAGE_FOLDER="${_TMP_PCKG_FOLDER}/ibm-content-assistant-client-managed-software-${CP4BA_INST_CACMS_PACKAGE_DYNAMIC_DOWNLOAD_VER}"
    rm ./${CP4BA_INST_CACMS_PACKAGE_DYNAMIC_DOWNLOAD_VER}.zip 2>/dev/null 1>/dev/null 
    cd ${_OLOC}
  fi

  if [[ ! -d "${CP4BA_INST_CACMS_PACKAGE_FOLDER}" ]]; then
    log_error "CACMS package installation folder not found"
    log_warning "Update variable CP4BA_INST_CACMS_PACKAGE_FOLDER or CP4BA_INST_CACMS_PACKAGE_DYNAMIC_DOWNLOAD_VER and restart this tool."  
    exit 1
  fi

  log_info "Using CACMS package folder '${_CLR_YELLOW}${CP4BA_INST_CACMS_PACKAGE_FOLDER}${_CLR_GREEN}'"

}

removeDynamicPackage() {
  if [[ $_IS_DYNAMIC_PACKAGE -eq 1 ]]; then
    if [[ -d "${CP4BA_INST_CACMS_PACKAGE_FOLDER}" ]]; then
      log_info "Removing CACMS dynamic package installation folder '${_CLR_YELLOW}${CP4BA_INST_CACMS_PACKAGE_FOLDER}${_CLR_GREEN}'"
    fi
  fi
}

log_msg "=============================================================="
setTemporaryFolder


if [[ "${_CMD}" = "install" ]]; then
  if [[ "${CP4BA_INST_CACMS_INSTALL}" = "true" ]]; then
    downloadOrVerifyPackage
    log_info "${_CLR_GREEN}Creating Content Assistant cluster in '${_CLR_YELLOW}${CP4BA_INST_NAMESPACE}${_CLR_GREEN}' namespace${_CLR_NC}"
    cacmsSetup
    log_info "${_CLR_GREEN}Content Assistant cluster is ready.${_CLR_NC}"
    removeDynamicPackage
  else
    log_warning "Cannot install Content Assistant, variable CP4BA_INST_CACMS_INSTALL not defined or false."
  fi
else
  if [[ "${_CMD}" = "remove" ]]; then
    log_info "${_CLR_GREEN}Removing Content Assistant cluster from '${_CLR_YELLOW}${CP4BA_INST_NAMESPACE}${_CLR_GREEN}' namespace${_CLR_NC}"
    cacmsRemoveResources
    log_info "${_CLR_GREEN}Content Assistant cluster no longer exists.${_CLR_NC}"
  else
    log_error "Command -k not valid"
    usage
    exit 1
  fi
fi
exit 0
