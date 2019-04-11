#!/bin/bash -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp/}$(basename ${0##*/} .sh).XXXXXXXXXXXX")

names_first=(`jq -r '.unicorn.first[]' ${script_dir}/names.json`)
names_middle=(`jq -r '.unicorn.middle[]' ${script_dir}/names.json`)
names_last=(`jq -r '.unicorn.last[]' ${script_dir}/names.json`)

zone_uri_list=(`gcloud compute zones list --uri`)
zone_name_list=("${zone_uri_list[@]##*/}")

_echo() {
  if [ -z "$TERM" ] || [[ "${HOSTNAME}" == "releng-gcp-provisioner-"* ]]; then
    message=${1//_bold_/}
    message=${message//_dim_/}
    message=${message//_reset_/}
    echo ${message}
  else
    script_name=$(basename ${0##*/} .sh)
    message=${1//_bold_/$(tput bold)}
    message=${message//_dim_/$(tput dim)}
    message=${message//_reset_/$(tput sgr0)}
    echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")]$(tput sgr0) ${message}"
  fi
}

_echo "temp_dir: _bold_${temp_dir}_reset_"

if command -v pass > /dev/null; then
  livelogSecret=`pass Mozilla/TaskCluster/livelogSecret`
  livelogcrt=`pass Mozilla/TaskCluster/livelogCert`
  livelogkey=`pass Mozilla/TaskCluster/livelogKey`
  pgpKey=`pass Mozilla/OpenCloudConfig/rootGpgKey`
  relengapiToken=`pass Mozilla/OpenCloudConfig/tooltool-relengapi-tok`
  occInstallersToken=`pass Mozilla/OpenCloudConfig/tooltool-occ-installers-tok`
elif curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes > /dev/null; then
  livelogSecret=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/livelogSecret")
  livelogcrt=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/livelogcrt")
  livelogkey=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/livelogkey")
  pgpKey=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/pgpKey")
  relengapiToken=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/relengapiToken")
  occInstallersToken=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/occInstallersToken")
else
  _echo "failed to determine a source for secrets"
  exit 1
fi
project_name=windows-workers
provisionerId=releng-hardware
GITHUB_HEAD_SHA=`git rev-parse HEAD`
deploymentId=${GITHUB_HEAD_SHA:0:12}

if [[ $@ == *"--open-in-browser"* ]] && which xdg-open > /dev/null; then
  xdg-open "https://console.cloud.google.com/compute/instances?authuser=1&folder&organizationId&project=${project_name}&instancessize=50&duration=PT1H&pli=1&instancessort=zoneForFilter%252Cname"
fi
_echo "deployment id: _bold_${deploymentId}_reset_"
for manifest in $(ls ${script_dir}/../userdata/Manifest/*-gamma.json); do
  workerType=$(basename ${manifest##*/} .json)
  _echo "worker type: _bold_${workerType}_reset_"
  if [[ ${workerType} =~ ^[a-zA-Z]*-([1-3])-.*$ ]]; then
    SCM_LEVEL=${BASH_REMATCH[1]}
  else
    SCM_LEVEL=0
  fi
  if command -v pass > /dev/null; then
    accessToken=`pass Mozilla/TaskCluster/project/releng/generic-worker/${workerType}/production`
    SCCACHE_GCS_KEY=`pass Mozilla/TaskCluster/gcp-service-account/taskcluster-level-${SCM_LEVEL}-sccache@${project_name}`
  elif curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes > /dev/null; then
    accessToken=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/access-token-${workerType}")
    SCCACHE_GCS_KEY=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/SCCACHE_GCS_KEY_${SCM_LEVEL}")
  else
    _echo "failed to determine a source for secrets_reset_"
    exit 1
  fi
  # determine the number of instances to spawn by checking the pending count for the worker type
  pendingTaskCount=$(curl -s "https://queue.taskcluster.net/v1/pending/${provisionerId}/${workerType}" | jq '.pendingTasks')
  _echo "${workerType} pending tasks: _bold_${pendingTaskCount}_reset_"

  # determine the number of instances already spawned that have not yet claimed tasks
  working_instance_count=0
  waiting_instance_count=0
  pending_instance_count=0
  zombied_instance_count=0
  goofing_instance_count=0
  deleted_instance_count=0
  running_instance_uri_list=(`gcloud compute instances list --uri --filter "labels.worker-type:${workerType} status:RUNNING" 2> /dev/null`)
  _echo "${workerType} running instances: _bold_${#running_instance_uri_list[@]}_reset_"
  for running_instance_uri in $(gcloud compute instances list --uri --filter "labels.worker-type:${workerType} status:RUNNING" 2> /dev/null); do
    running_instance_name=${running_instance_uri##*/}
    running_instance_zone_uri=${running_instance_uri/\/instances\/${running_instance_name}/}
    running_instance_zone=${running_instance_zone_uri##*/}
    running_instance_creation_timestamp=$(gcloud compute instances describe ${running_instance_name} --zone ${running_instance_zone} --format json | jq -r '.creationTimestamp')
    if [ -n "${running_instance_creation_timestamp}" ] && [[ "${running_instance_creation_timestamp}" != "null" ]]; then
      running_instance_uptime_minutes=$(( ($(date +%s) - $(date -d ${running_instance_creation_timestamp} +%s)) / 60))
      if [ "${running_instance_uptime_minutes}" -gt "60" ]; then
        running_instance_uptime="$((${running_instance_uptime_minutes} / 60)) hours, $((${running_instance_uptime_minutes} % 60)) minutes"
      else
        running_instance_uptime="${running_instance_uptime_minutes} minutes"
      fi
      curl -s -o ${temp_dir}/${workerType}.json "https://queue.taskcluster.net/v1/provisioners/${provisionerId}/worker-types/${workerType}/workers"
      if [ $(cat ${temp_dir}/${workerType}.json | jq --arg workerId ${running_instance_name} '[.workers[] | select(.workerId == $workerId)] | length') -gt 0 ]; then
        firstClaim=$(cat ${temp_dir}/${workerType}.json | jq -c --arg workerId ${running_instance_name} '.workers[] | select(.workerId == $workerId) | .firstClaim')
        lastTaskId=$(cat ${temp_dir}/${workerType}.json | jq -r --arg workerId ${running_instance_name} '.workers[] | select(.workerId == $workerId) | .latestTask.taskId')
        lastTaskRunId=$(cat ${temp_dir}/${workerType}.json | jq -r --arg workerId ${running_instance_name} '.workers[] | select(.workerId == $workerId) | .latestTask.runId')
        curl -s -o ${temp_dir}/${lastTaskId}.json "https://queue.taskcluster.net/v1/task/${lastTaskId}/status"
        lastTaskResolvedTime=$(cat ${temp_dir}/${lastTaskId}.json | jq --arg runId ${lastTaskRunId} -r '.status.runs[]? | select(.runId == ($runId | tonumber)) | .resolved')
        lastTaskStartedTime=$(cat ${temp_dir}/${lastTaskId}.json | jq --arg runId ${lastTaskRunId} -r '.status.runs[]? | select(.runId == ($runId | tonumber)) | .started')
        if [ -n "${lastTaskResolvedTime}" ] && [[ "${lastTaskResolvedTime}" != "null" ]]; then
          wait_time_minutes=$(( ($(date +%s) - $(date -d ${lastTaskResolvedTime} +%s)) / 60))
          if [ "${wait_time_minutes}" -gt "60" ]; then
            wait_time="$((${wait_time_minutes} / 60)) hours, $((${wait_time_minutes} % 60)) minutes"
          else
            wait_time="${wait_time_minutes} minutes"
          fi
          if [ "${wait_time_minutes}" -gt "60" ] && gcloud compute instances delete ${running_instance_name} --zone ${running_instance_zone} --delete-disks all --quiet 2> /dev/null; then
            _echo "${workerType} waiting instance deleted: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp}). resolved task: _bold_${lastTaskId}/${lastTaskRunId}_reset_, ${wait_time} ago (at ${lastTaskResolvedTime})"
          else
            _echo "${workerType} waiting instance detected: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp}). resolved task: _bold_${lastTaskId}/${lastTaskRunId}_reset_, ${wait_time} ago (at ${lastTaskResolvedTime})"
          fi
          (( waiting_instance_count = waiting_instance_count + 1 ))
        elif [ -n "${lastTaskStartedTime}" ] && [[ "${lastTaskStartedTime}" != "null" ]]; then
          work_time_minutes=$(( ($(date +%s) - $(date -d ${lastTaskStartedTime} +%s)) / 60))
          if [ "${work_time_minutes}" -gt "60" ]; then
            work_time="$((${work_time_minutes} / 60)) hours, $((${work_time_minutes} % 60)) minutes"
          else
            work_time="${work_time_minutes} minutes"
          fi
          _echo "${workerType} working instance detected: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp}). running task: _bold_${lastTaskId}/${lastTaskRunId}_reset_, for ${work_time} (since ${lastTaskStartedTime})"
          (( working_instance_count = working_instance_count + 1 ))
        else
          _echo "${workerType} goofing instance detected: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp}). $(cat ${temp_dir}/${workerType}.json | jq -c --arg workerId ${running_instance_name} '.workers[] | select(.workerId == $workerId)')"
          (( goofing_instance_count = goofing_instance_count + 1 ))
        fi
      elif [ "${running_instance_uptime_minutes}" -lt "30" ]; then
        _echo "${workerType} pending instance detected: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp})"
        (( pending_instance_count = pending_instance_count + 1 ))
      elif gcloud compute instances delete ${running_instance_name} --zone ${running_instance_zone} --delete-disks all --quiet 2> /dev/null; then
        _echo "${workerType} zombied instance deleted: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp})"
        (( zombied_instance_count = zombied_instance_count + 1 ))
      else
        _echo "${workerType} zombied instance detected: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp})"
        (( zombied_instance_count = zombied_instance_count + 1 ))
      fi
    elif [ -n "${firstClaim}" ] && [[ "${firstClaim}" != "null" ]]; then
      wait_time_minutes=$(( ($(date +%s) - $(date -d ${firstClaim} +%s)) / 60))
      if [ "${wait_time_minutes}" -gt "60" ]; then
        wait_time="$((${wait_time_minutes} / 60)) hours, $((${wait_time_minutes} % 60)) minutes"
      else
        wait_time="${wait_time_minutes} minutes"
      fi
      if [ "${wait_time_minutes}" -gt "60" ] && gcloud compute instances delete ${running_instance_name} --zone ${running_instance_zone} --delete-disks all --quiet 2> /dev/null; then
        _echo "${workerType} virgin instance deleted: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp}). first claim: _bold_${lastTaskId}/${lastTaskRunId}_reset_, ${wait_time} ago (at ${firstClaim})"
      else
        _echo "${workerType} virgin instance detected: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp}). first claim: _bold_${lastTaskId}/${lastTaskRunId}_reset_, ${wait_time} ago (at ${firstClaim})"
      fi
      (( waiting_instance_count = waiting_instance_count + 1 ))
    else
      _echo "${workerType} deleted instance detected: _bold_${running_instance_name}_reset_ in _bold_${running_instance_zone}_reset_ with uptime: unknown"
      (( deleted_instance_count = deleted_instance_count + 1 ))
    fi
  done
  if [ "${waiting_instance_count}" -gt "0" ]; then
    _echo "${workerType} waiting instances: _bold_${waiting_instance_count}_reset_"
  fi
  if [ "${working_instance_count}" -gt "0" ]; then
    _echo "${workerType} working instances: _bold_${working_instance_count}_reset_"
  fi
  if [ "${pending_instance_count}" -gt "0" ]; then
    _echo "${workerType} pending instances: _bold_${pending_instance_count}_reset_"
  fi
  if [ "${zombied_instance_count}" -gt "0" ]; then
    _echo "${workerType} zombied instances: _bold_${zombied_instance_count}_reset_"
  fi
  if [ "${goofing_instance_count}" -gt "0" ]; then
    _echo "${workerType} goofing instances: _bold_${goofing_instance_count}_reset_"
  fi
  if [ "${deleted_instance_count}" -gt "0" ]; then
    _echo "${workerType} deleted instances: _bold_${deleted_instance_count}_reset_"
  fi
  required_instance_count=0
  if [ "${pending_instance_count}" -lt "${pendingTaskCount}" ]; then
    (( required_instance_count = pendingTaskCount - pending_instance_count ))
  fi
  _echo "${workerType} required instances: _bold_${required_instance_count}_reset_"
  if [ "${required_instance_count}" -gt "0" ]; then
    # spawn some instances
    for i in $(seq 1 ${required_instance_count}); do
      # pick a random machine type from the list of machine types in the provisioner configuration of the manifest
      instanceTypes=(`jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.machine_types[]' ${manifest}`)
      instanceType=${instanceTypes[$[$RANDOM % ${#instanceTypes[@]}]]}
      instanceCpuCount=${instanceType##*-}
      # pick a random zone that has region cpu quota (minus usage) higher than required instanceCpuCount
      zone_name=${zone_name_list[$[$RANDOM % ${#zone_name_list[@]}]]}
      region=${zone_name::-2}
      cpuQuota=$(gcloud compute regions describe ${region} --project ${project_name} --format json | jq '.quotas[] | select(.metric == "CPUS").limit')
      cpuUsage=$(gcloud compute regions describe ${region} --project ${project_name} --format json | jq '.quotas[] | select(.metric == "CPUS").usage')
      while (( (cpuQuota - cpuUsage) < instanceCpuCount )); do
        _echo "skipping region: ${region} (cpu quota: ${cpuQuota}, cpu usage: ${cpuUsage})_reset_"
        zone_name=${zone_name_list[$[$RANDOM % ${#zone_name_list[@]}]]}
        region=${zone_name::-2}
        cpuQuota=$(gcloud compute regions describe ${region} --project ${project_name} --format json | jq '.quotas[] | select(.metric == "CPUS").limit')
        cpuUsage=$(gcloud compute regions describe ${region} --project ${project_name} --format json | jq '.quotas[] | select(.metric == "CPUS").usage')
      done
      # set sccache configuration
      SCCACHE_GCS_BUCKET=taskcluster-level-${SCM_LEVEL}-sccache-${region}
      # generate a random instance name which does not pre-exist
      existing_instance_uri_list=(`gcloud compute instances list --uri`)
      existing_instance_name_list=("${existing_instance_uri_list[@]##*/}")
      instance_name=${names_first[$[$RANDOM % ${#names_first[@]}]]}-${names_middle[$[$RANDOM % ${#names_middle[@]}]]}-${names_last[$[$RANDOM % ${#names_last[@]}]]}
      while [[ " ${existing_instance_name_list[@]} " =~ " ${instance_name} " ]]; do
        instance_name=${names_first[$[$RANDOM % ${#names_first[@]}]]}-${names_middle[$[$RANDOM % ${#names_middle[@]}]]}-${names_last[$[$RANDOM % ${#names_last[@]}]]}
      done
      _echo "instance name: _bold_${instance_name}_reset_"
      _echo "zone name: _bold_${zone_name}_reset_"
      _echo "region: _bold_${region}_reset_"
      _echo "instance type: _bold_${instanceType}_reset_"
      _echo "worker group: _bold_${region}_reset_"
      _echo "worker type: _bold_${workerType}_reset_"

      disk_zero_size=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.boot.size' ${manifest})
      disk_zero_type=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.boot.type' ${manifest})

      disk_one_type=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.supplementary[0].type' ${manifest})

      if [[ "${disk_one_type}" == "local-ssd" ]]; then
        disk_one_interface=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.supplementary[0].interface' ${manifest})
        gcloud compute instances create ${instance_name} \
          --image-project windows-cloud \
          --image-family windows-2012-r2 \
          --machine-type ${instanceType} \
          --boot-disk-size ${disk_zero_size} \
          --boot-disk-type ${disk_zero_type} \
          --local-ssd interface=${disk_one_interface} \
          --scopes storage-ro \
          --service-account taskcluster-level-${SCM_LEVEL}-sccache@${project_name}.iam.gserviceaccount.com \
          --metadata "^;^windows-startup-script-url=gs://open-cloud-config/gcloud-startup.ps1;workerType=${workerType};sourceOrg=mozilla-releng;sourceRepo=OpenCloudConfig;sourceRevision=gamma;pgpKey=${pgpKey};livelogkey=${livelogkey};livelogcrt=${livelogcrt};relengapiToken=${relengapiToken};occInstallersToken=${occInstallersToken};SCCACHE_GCS_BUCKET=${SCCACHE_GCS_BUCKET};SCCACHE_GCS_KEY=${SCCACHE_GCS_KEY}" \
          --zone ${zone_name} \
          --preemptible
      else
        gcloud compute instances create ${instance_name} \
          --image-project windows-cloud \
          --image-family windows-2012-r2 \
          --machine-type ${instanceType} \
          --boot-disk-size ${disk_zero_size} \
          --boot-disk-type ${disk_zero_type} \
          --scopes storage-ro \
          --service-account taskcluster-level-${SCM_LEVEL}-sccache@${project_name}.iam.gserviceaccount.com \
          --metadata "^;^windows-startup-script-url=gs://open-cloud-config/gcloud-startup.ps1;workerType=${workerType};sourceOrg=mozilla-releng;sourceRepo=OpenCloudConfig;sourceRevision=gamma;pgpKey=${pgpKey};livelogkey=${livelogkey};livelogcrt=${livelogcrt};relengapiToken=${relengapiToken};occInstallersToken=${occInstallersToken};SCCACHE_GCS_BUCKET=${SCCACHE_GCS_BUCKET};SCCACHE_GCS_KEY=${SCCACHE_GCS_KEY}" \
          --zone ${zone_name} \
          --preemptible
        disk_one_size=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.supplementary[0].size' ${manifest})
        gcloud beta compute disks create ${instance_name}-disk-1 --type ${disk_one_type} --size ${disk_one_size} --zone ${zone_name}
        gcloud compute instances attach-disk ${instance_name} --disk ${instance_name}-disk-1 --zone ${zone_name}
      fi

      publicIP=$(gcloud compute instances describe ${instance_name} --zone ${zone_name} --format json | jq -r '.networkInterfaces[0].accessConfigs[0].natIP')
      _echo "public ip: _bold_${publicIP}_reset_"
      privateIP=$(gcloud compute instances describe ${instance_name} --zone ${zone_name} --format json | jq -r '.networkInterfaces[0].networkIP')
      _echo "private ip: _bold_${privateIP}_reset_"
      instanceId=$(gcloud compute instances describe ${instance_name} --zone ${zone_name} --format json | jq -r '.id')
      _echo "instance id: _bold_${instanceId}_reset_"
      gwConfig="`curl -s https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/gamma/userdata/Manifest/${workerType}.json | jq --arg accessToken ${accessToken} --arg livelogSecret ${livelogSecret} --arg publicIP ${publicIP} --arg privateIP ${privateIP} --arg workerId ${instance_name} --arg provisionerId ${provisionerId} --arg region ${region} --arg deploymentId ${deploymentId} --arg availabilityZone ${zone_name} --arg instanceId ${instanceId} --arg instanceType ${instanceType} -c '.ProvisionerConfiguration.userData.genericWorker.config | .accessToken = $accessToken | .livelogSecret = $livelogSecret | .publicIP = $publicIP | .privateIP = $privateIP | .workerId = $workerId | .instanceId = $instanceId | .instanceType = $instanceType | .availabilityZone = $availabilityZone | .region = $region | .provisionerId = $provisionerId | .workerGroup = $region | .deploymentId = $deploymentId' | sed 's/\"/\\\"/g'`"
      gcloud compute instances add-metadata ${instance_name} --zone ${zone_name} --metadata "^;^gwConfig=${gwConfig}"
      gcloud compute instances add-labels ${instance_name} --zone ${zone_name} --labels=worker-type=${workerType}
    done
  fi
done
# delete instances that have been terminated
for terminated_instance_uri in $(gcloud compute instances list --uri --filter status:TERMINATED 2> /dev/null); do
  terminated_instance_name=${terminated_instance_uri##*/}
  terminated_instance_zone_uri=${terminated_instance_uri/\/instances\/${terminated_instance_name}/}
  terminated_instance_zone=${terminated_instance_zone_uri##*/}
  if [ -n "${terminated_instance_name}" ] && [ -n "${terminated_instance_zone}" ] && gcloud compute instances delete ${terminated_instance_name} --zone ${terminated_instance_zone} --delete-disks all --quiet 2> /dev/null; then
    _echo "deleted: _bold_${terminated_instance_zone}/${terminated_instance_name}_reset_"
  fi
done
# delete orphaned disks
for orphaned_disk_uri in $(gcloud compute disks list --uri --filter "-users:*" 2> /dev/null); do
  orphaned_disk_name=${orphaned_disk_uri##*/}
  orphaned_disk_zone_uri=${orphaned_disk_uri/\/disks\/${orphaned_disk_name}/}
  orphaned_disk_zone=${orphaned_disk_zone_uri##*/}
  if [ -n "${orphaned_disk_name}" ] && [ -n "${orphaned_disk_zone}" ] && gcloud compute disks delete ${orphaned_disk_name} --zone ${orphaned_disk_zone} --quiet 2> /dev/null; then
    _echo "deleted: _bold_${orphaned_disk_zone}/${orphaned_disk_name}_reset_"
  fi
done
# open the firewall to livelog traffic
if [[ "$(gcloud compute firewall-rules list --filter name:livelog-direct --format json)" == "[]" ]]; then
  gcloud compute firewall-rules create livelog-direct --allow tcp:60023 --description "allows connections to livelog GET interface, running on taskcluster worker instances"
fi

rm -rf ${temp_dir}