#!/bin/bash

temp_dir=$(mktemp -d)
current_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
current_script_name=$(basename ${0##*/} .sh)

echo ${temp_dir}

rm -f ${current_script_dir}/../cfg/generic-worker/*.json.gpg
rm -f ${current_script_dir}/../cfg/OpenCloudConfig.private.key.gpg
rm -f ${current_script_dir}/../cfg/bitbar/.*.pw.gpg

mkdir -p ${temp_dir}/gnupg
chmod 700 ${temp_dir}/gnupg

rootURL=https://firefox-ci-tc.services.mozilla.com

for pub_key_path in ${current_script_dir}/../keys/*; do
  workerId=$(basename ${pub_key_path})
  if [[ "${workerId}" == "vm-"* ]]; then
    if az vm show --resource-group rg-east-us-gecko-t -n ${workerId} --query tags.workerType > /dev/null 2>&1; then
      workerType=$(az vm show --resource-group rg-east-us-gecko-t -n ${workerId} --query tags.workerType --output tsv)
    elif az vm show --resource-group rg-east-us-gecko-1 -n ${workerId} --query tags.workerType > /dev/null 2>&1; then
      workerType=$(az vm show --resource-group rg-east-us-gecko-1 -n ${workerId} --query tags.workerType --output tsv)
    else
      echo "failed to determine worker type and client id"
      exit
    fi
    clientId=project/releng/generic-worker/azure-${workerType/-azure/}
    accessToken=$(pass Mozilla/TaskCluster/client/${clientId})
    provisionerId=azure
    workerGroup=azure
    taskDrive=Z
  else
    accessToken=$(pass Mozilla/TaskCluster/client/project/releng/generic-worker/bitbar-gecko-t-win10-aarch64)
    clientId=project/releng/generic-worker/bitbar-gecko-t-win10-aarch64
    provisionerId=bitbar
    workerGroup=bitbar-sc
    workerType=gecko-t-win64-aarch64-laptop
    taskDrive=C
  fi
  echo ${workerId}
  if [[ "${workerId}" == "vm-"* ]]; then
    recipient=${workerId}
    publicIP=$(az vm list-ip-addresses -n ${workerId} | jq -r '.[0].virtualMachine.network.publicIpAddresses[0].ipAddress')
  elif [[ "${workerId}" == "desktop-"* ]]; then
    recipient=${workerId}
    publicIP=0.0.0.0
  elif [[ "${workerId}" == "t-lenovoyogac630-"* ]]; then
    # most instances have an ip address of 10.7.204.(instance-number + 20) but there are exceptions.
    workerNumberPadded=${workerId/t-lenovoyogac630-/}
    workerNumber=$((10#$workerNumberPadded))
    recipient=yoga-${workerNumberPadded}
    if [ "${workerId}" == "t-lenovoyogac630-003" ]; then
      publicIP=10.7.205.32
    elif [ "${workerId}" == "t-lenovoyogac630-012" ]; then
      publicIP=10.7.205.85
    elif [ "${workerId}" == "t-lenovoyogac630-020" ]; then
      publicIP=10.7.205.48
    else
      publicIP=10.7.204.$(( 20 + workerNumber ))
    fi
  fi
  gpg2 --homedir ${temp_dir}/gnupg --import ${pub_key_path}
  jq --sort-keys \
    --arg accessToken ${accessToken} \
    --arg clientId ${clientId} \
    --arg provisionerId ${provisionerId} \
    --arg publicIP ${publicIP} \
    --arg rootURL ${rootURL} \
    --arg taskDrive ${taskDrive} \
    --arg workerGroup ${workerGroup} \
    --arg workerId ${workerId} \
    --arg workerType ${workerType} \
    '. | .accessToken = $accessToken | .clientId = $clientId | .provisionerId = $provisionerId | .publicIP = $publicIP | .rootURL = $rootURL | .workerGroup = $workerGroup | .workerId = $workerId | .workerType = $workerType | .cachesDir = $taskDrive + ":\\caches" | .downloadsDir = $taskDrive + ":\\downloads" | .tasksDir = $taskDrive + ":\\tasks"' \
    ${current_script_dir}/../userdata/Configuration/GenericWorker/generic-worker.config > ${current_script_dir}/../cfg/generic-worker/${workerId}.json
  if [ ! -f ${current_script_dir}/../cfg/generic-worker/${workerId}.json.gpg ]; then
    gpg2 --homedir ${temp_dir}/gnupg --batch --output ${current_script_dir}/../cfg/generic-worker/${workerId}.json.gpg --encrypt --recipient ${recipient} --trust-model always ${current_script_dir}/../cfg/generic-worker/${workerId}.json
  else
    echo detected previously encrypted file ${current_script_dir}/../cfg/generic-worker/${workerId}.json.gpg with recipient: $(gpg2 --list-only -v -d ${current_script_dir}/../cfg/generic-worker/${workerId}.json.gpg 2>&1 | grep RSA | awk '{print $7}' ORS=' ')
  fi
done
recipientList=$(gpg2 --homedir ${temp_dir}/gnupg --list-keys --with-colons --fast-list-mode | awk -F: '/^pub/{printf "-r %s ", $5}')
if [ ! -f ${current_script_dir}/../cfg/OpenCloudConfig.private.key.gpg ]; then
  gpg2 --homedir ${temp_dir}/gnupg --batch --output ${current_script_dir}/../cfg/OpenCloudConfig.private.key.gpg --encrypt ${recipientList} --trust-model always ${current_script_dir}/../cfg/OpenCloudConfig.private.key
else
  echo detected previously encrypted file ${current_script_dir}/../cfg/OpenCloudConfig.private.key.gpg with recipients: $(gpg2 --list-only -v -d ${current_script_dir}/../cfg/OpenCloudConfig.private.key.gpg 2>&1 | grep RSA | awk '{print $7}' ORS=' ')
fi
for bb_pw_path in ${current_script_dir}/../cfg/bitbar/.*.pw; do
  if [ ! -f ${bb_pw_path}.gpg ]; then
    gpg2 --homedir ${temp_dir}/gnupg --batch --output ${bb_pw_path}.gpg --encrypt ${recipientList} --trust-model always ${bb_pw_path}
  else
    echo detected previously encrypted file ${bb_pw_path}.gpg with recipients: $(gpg2 --list-only -v -d ${bb_pw_path}.gpg 2>&1 | grep RSA | awk '{print $7}' ORS=' ')
  fi
done
rm -rf ${temp_dir}
echo ''