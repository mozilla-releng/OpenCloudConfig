#!/bin/bash -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp/}$(basename ${0##*/} .sh).XXXXXXXXXXXX")

# create a logging function that outputs easily readable console messages but strips formatting when logging to papertrail
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

# set up the list of google cloud zones we will instantiate and manage instances within
zone_uri_list=(`gcloud compute zones list --uri --filter name:us-*`)
zone_name_list=("${zone_uri_list[@]##*/}")

_echo "temp_dir: _bold_${temp_dir}_reset_"

# obtain secrets from the local password store when running on a workstation and obtain them from google cloud metadata server when running on provisioners
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

# set up some configuration data
project_name=windows-workers
GITHUB_HEAD_SHA=`git rev-parse HEAD`
deploymentId=${GITHUB_HEAD_SHA:0:12}

# open a local browser tab to the gcloud vm instance list for the current project if the run command has the appropriate arg
if [[ $@ == *"--open-in-browser"* ]] && which xdg-open > /dev/null; then
  xdg-open "https://console.cloud.google.com/compute/instances?authuser=1&folder&organizationId&project=${project_name}&instancessize=50&duration=PT1H&pli=1&instancessort=zoneForFilter%252Cname"
fi
_echo "deployment id: _bold_${deploymentId}_reset_"

# iterate through each worker type containing a "-gamma" suffix in the occ manifest directory
for manifest in $(ls ${script_dir}/../userdata/Manifest/*-gamma.json | shuf); do
  workerType=$(basename ${manifest##*/} .json)
  workerImplementation=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.worker_implementation' ${manifest})
  provisionerId=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.provisioner_id' ${manifest})
  _echo "worker type: _bold_${workerType}_reset_"

  # determine the scm level from the worker type name
  if [[ ${workerType} =~ ^gecko-([1-3])-b-.*$ ]]; then
    SCM_LEVEL=${BASH_REMATCH[1]}
  else
    SCM_LEVEL=0
  fi

  # obtain worker type specific secrets from the local password store when running on a workstation and obtain them from google cloud metadata server when running on provisioners
  if command -v pass > /dev/null; then
    accessToken=`pass Mozilla/TaskCluster/project/releng/${workerImplementation}/${workerType}/production`
    if [[ "${SCM_LEVEL}" != "0" ]]; then
      SCCACHE_GCS_KEY=`pass Mozilla/TaskCluster/gcp-service-account/taskcluster-level-${SCM_LEVEL}-sccache@${project_name}`
    fi
  elif curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes > /dev/null; then
    accessToken=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/access-token-${workerType}")
    if [[ "${SCM_LEVEL}" != "0" ]]; then
      SCCACHE_GCS_KEY=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/SCCACHE_GCS_KEY_${SCM_LEVEL}")
    fi
  else
    _echo "failed to determine a source for secrets_reset_"
    exit 1
  fi

  # determine the number of instances already running and what state they are in

  # count of instances currently processing a task
  working_instance_count=0

  # count of instances currently waiting for a task to process
  waiting_instance_count=0

  # count of instances currently initialising or booting up for the first time
  pending_instance_count=0

  # count of instances which have not registered a first claim with the taskcluster queue but have been running long enough to have done so
  zombied_instance_count=0

  # count of instances in an unknown state
  goofing_instance_count=0

  # count of instances that have already been deleted (probably by another provisioner instance) by the time we attempt state discovery
  deleted_instance_count=0

  idle_termination_interval=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.idle_termination_threshold.interval' ${manifest})
  _echo "${workerType} idle termination after: _bold_${idle_termination_interval} minutes_reset_"
  # iterate all instances of the current worker type which are in a running state
  for running_instance_uri in $(gcloud compute instances list --uri --filter "labels.worker-type:${workerType} status:RUNNING" 2> /dev/null | shuf); do
    running_instance_name=${running_instance_uri##*/}
    running_instance_zone_uri=${running_instance_uri/\/instances\/${running_instance_name}/}
    running_instance_zone=${running_instance_zone_uri##*/}
    if gcloud compute instances describe ${running_instance_name} --zone ${running_instance_zone} --format json > ${temp_dir}/${running_instance_zone}-${running_instance_name}.json 2> /dev/null; then
      running_instance_creation_timestamp=$(date --utc -d $(cat ${temp_dir}/${running_instance_zone}-${running_instance_name}.json | jq -r '.creationTimestamp') +%FT%T.%3NZ)
      running_instance_deployment_id=$(cat ${temp_dir}/${running_instance_zone}-${running_instance_name}.json | jq -r '.labels."deployment-id" // empty')
      # calculate uptime based on gcloud creation timestamp
      running_instance_uptime_minutes=$(( ($(date +%s) - $(date -d ${running_instance_creation_timestamp} +%s)) / 60))
      if [ "${running_instance_uptime_minutes}" -gt "60" ]; then
        running_instance_uptime="$((${running_instance_uptime_minutes} / 60)) hours, $((${running_instance_uptime_minutes} % 60)) minutes"
      else
        running_instance_uptime="${running_instance_uptime_minutes} minutes"
      fi
      curl -s -o ${temp_dir}/${workerType}.json "https://queue.taskcluster.net/v1/provisioners/${provisionerId}/worker-types/${workerType}/workers"
      if [[ "${workerImplementation}" == "docker-worker" ]]; then
        instance_id=$(cat ${temp_dir}/${running_instance_zone}-${running_instance_name}.json | jq -r '.id')
        worker_id=${instance_id::-4}
      else
        worker_id=${running_instance_name}
      fi
      if [ $(cat ${temp_dir}/${workerType}.json | jq --arg workerId ${worker_id} '[.workers[] | select(.workerId | startswith($workerId))] | length') -gt 0 ]; then
        first_claim=$(cat ${temp_dir}/${workerType}.json | jq -r --arg workerId ${worker_id} '.workers[] | select(.workerId | startswith($workerId)) | .firstClaim')
        last_task_id=$(cat ${temp_dir}/${workerType}.json | jq -r --arg workerId ${worker_id} '.workers[] | select(.workerId | startswith($workerId)) | .latestTask.taskId')
        last_task_run_id=$(cat ${temp_dir}/${workerType}.json | jq -r --arg workerId ${worker_id} '.workers[] | select(.workerId | startswith($workerId)) | .latestTask.runId')
        curl -s -o ${temp_dir}/${last_task_id}.json "https://queue.taskcluster.net/v1/task/${last_task_id}/status"
        last_task_run_state=$(cat ${temp_dir}/${last_task_id}.json | jq --arg runId ${last_task_run_id} -r '.status.runs[]? | select(.runId == ($runId | tonumber)) | .state')
        last_task_run_started_time=$(cat ${temp_dir}/${last_task_id}.json | jq --arg runId ${last_task_run_id} -r '.status.runs[]? | select(.runId == ($runId | tonumber)) | .started')
        last_task_run_created_reason=$(cat ${temp_dir}/${last_task_id}.json | jq --arg runId ${last_task_run_id} -r '.status.runs[]? | select(.runId == ($runId | tonumber)) | .reasonCreated')
        if [ -n "${last_task_run_state}" ] && [[ "${last_task_run_state}" != "running" ]]; then
          last_task_run_resolved_time=$(cat ${temp_dir}/${last_task_id}.json | jq --arg runId ${last_task_run_id} -r '.status.runs[]? | select(.runId == ($runId | tonumber)) | .resolved')
          last_task_run_resolved_reason=$(cat ${temp_dir}/${last_task_id}.json | jq --arg runId ${last_task_run_id} -r '.status.runs[]? | select(.runId == ($runId | tonumber)) | .reasonResolved')
          wait_time_minutes=$(( ($(date +%s) - $(date -d ${last_task_run_resolved_time} +%s)) / 60))
          if [ "${wait_time_minutes}" -gt "60" ]; then
            wait_time="$((${wait_time_minutes} / 60)) hours, $((${wait_time_minutes} % 60)) minutes"
          else
            wait_time="${wait_time_minutes} minutes"
          fi
          if [ "$(date -d ${last_task_run_started_time} +%s)" -lt "$(date -d ${last_task_run_resolved_time} +%s)" ] && [ "${wait_time_minutes}" -gt "${idle_termination_interval}" ] && gcloud compute instances delete ${running_instance_name} --zone ${running_instance_zone} --delete-disks all --quiet 2> /dev/null; then
            # reaching here indicates the instance has been waiting for work to do for more than ${idle_termination_interval} minutes, so we've killed it
            _echo "${workerType} waiting instance deleted: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id}). resolved ${last_task_run_created_reason} task: _bold_${last_task_id}/${last_task_run_id}_reset_ with status: ${last_task_run_resolved_reason}, ${wait_time} ago (at ${last_task_run_resolved_time})"
          elif [ "$(date -d ${last_task_run_started_time} +%s)" -lt "$(date -d ${last_task_run_resolved_time} +%s)" ] && [[ "${running_instance_deployment_id}" != "${deploymentId}" ]] && gcloud compute instances delete ${running_instance_name} --zone ${running_instance_zone} --delete-disks all --quiet 2> /dev/null; then
            # reaching here indicates the instance has been waiting for work to do however the occ repo has changed since this instance was deployed, so we've killed it
            _echo "${workerType} expired instance deleted: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from expired sha: ${running_instance_deployment_id}). resolved ${last_task_run_created_reason} task: _bold_${last_task_id}/${last_task_run_id}_reset_ with status: ${last_task_run_resolved_reason}, ${wait_time} ago (at ${last_task_run_resolved_time})"
          else
            # reaching here indicates another provisioner has beaten us to killing this instance or the instance has been waiting for work for less than ${idle_termination_interval} minutes and can be left to continue waiting for work
            _echo "${workerType} waiting instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id}). resolved ${last_task_run_created_reason} task: _bold_${last_task_id}/${last_task_run_id}_reset_ with status: ${last_task_run_resolved_reason}, ${wait_time} ago (at ${last_task_run_resolved_time})"
          fi
          (( waiting_instance_count = waiting_instance_count + 1 ))
        elif [[ "${last_task_run_state}" == "running" ]]; then
          work_time_minutes=$(( ($(date +%s) - $(date -d ${last_task_run_started_time} +%s)) / 60))
          if [ "${work_time_minutes}" -gt "60" ]; then
            work_time="$((${work_time_minutes} / 60)) hours, $((${work_time_minutes} % 60)) minutes"
          else
            work_time="${work_time_minutes} minutes"
          fi
          _echo "${workerType} working instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id}). running ${last_task_run_created_reason} task: _bold_${last_task_id}/${last_task_run_id}_reset_, for ${work_time} (since ${last_task_run_started_time})"
          (( working_instance_count = working_instance_count + 1 ))
        elif [ -n "${first_claim}" ] && date -d ${first_claim} +%s &> /dev/null; then
          wait_time_minutes=$(( ($(date +%s) - $(date -d ${first_claim} +%s)) / 60))
          if [ "${wait_time_minutes}" -gt "60" ]; then
            wait_time="$((${wait_time_minutes} / 60)) hours, $((${wait_time_minutes} % 60)) minutes"
          else
            wait_time="${wait_time_minutes} minutes"
          fi
          if [ "${wait_time_minutes}" -gt "${idle_termination_interval}" ] && gcloud compute instances delete ${running_instance_name} --zone ${running_instance_zone} --delete-disks all --quiet 2> /dev/null; then
            # reaching here indicates the instance has been waiting for work to do for more than ${idle_termination_interval} minutes, without ever taking a task, so we've killed it
            _echo "${workerType} waiting instance deleted: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id}). first claim ${wait_time} ago (at ${first_claim})"
          else
            _echo "${workerType} waiting instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id}). first claim ${wait_time} ago (at ${first_claim})"
            (( waiting_instance_count = waiting_instance_count + 1 ))
          fi
        else
          _echo "${workerType} goofing instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id}). worker: $(cat ${temp_dir}/${workerType}.json | jq -c --arg workerId ${running_instance_name} '.workers[] | select(.workerId | startswith($workerId))'); task run: $(cat ${temp_dir}/${last_task_id}.json | jq -c --arg runId ${last_task_run_id} -r '.status.runs[]? | select(.runId == ($runId | tonumber))')"
          (( goofing_instance_count = goofing_instance_count + 1 ))
        fi
      elif [ "${running_instance_uptime_minutes}" -lt "30" ]; then
        # reaching here indicates the instance is not known to the queue (no first claim registered), however the instance has been running for less than 30 minutes
        _echo "${workerType} pending instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id})"
        (( pending_instance_count = pending_instance_count + 1 ))
      elif gcloud compute instances delete ${running_instance_name} --zone ${running_instance_zone} --delete-disks all --quiet 2> /dev/null; then
        # reaching here indicates the instance is not known to the queue (no first claim registered), however the instance has been running for more than 30 minutes and can be considered defective, hence deleted
        _echo "${workerType} zombied instance deleted: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id})"
        (( zombied_instance_count = zombied_instance_count + 1 ))
      elif [[ "${workerImplementation}" == "generic-worker" ]]; then
        # reaching here indicates the instance is not known to the queue (no first claim registered), however the instance has been running for more than 30 minutes and can be considered defective. our delete attempt failed probably due to another provisioner making a successful delete earlier
        _echo "${workerType} zombied instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id})"
        (( zombied_instance_count = zombied_instance_count + 1 ))
      elif [[ "${workerImplementation}" == "docker-worker" ]]; then
        # reaching here indicates the instance is a docker-worker and we haven't mapped it's worker id to its hostname
        _echo "${workerType} docker instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id})"
      else
        # reaching here indicates the instance is not known to the queue (no first claim registered), however the instance has been running for more than 30 minutes and can be considered defective. our delete attempt failed probably due to another provisioner making a successful delete earlier
        _echo "${workerType} zombied instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: _bold_${running_instance_uptime}_reset_ (created: ${running_instance_creation_timestamp} from sha: ${running_instance_deployment_id})"
        (( zombied_instance_count = zombied_instance_count + 1 ))
      fi
    else
      # reaching here indicates the instance has already been deleted (probably by another provisioner) because the describe instance query has failed
      _echo "${workerType} deleted instance observed: _bold_${running_instance_name}_reset_ (${worker_id}) in _bold_${running_instance_zone}_reset_ with uptime: unknown"
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

  capacity_minimum=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.capacity.minimum' ${manifest})
  _echo "${workerType} minimum capacity: _bold_${capacity_minimum}_reset_"
  capacity_maximum=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.capacity.maximum' ${manifest})
  _echo "${workerType} maximum capacity: _bold_${capacity_maximum}_reset_"

  running_instance_uri_list=(`gcloud compute instances list --uri --filter "labels.worker-type:${workerType} status:RUNNING" 2> /dev/null`)
  running_instance_count=${#running_instance_uri_list[@]}
  _echo "${workerType} running instances: _bold_${running_instance_count}_reset_"

  # determine the pending task count specific to the worker type
  pending_task_count=$(curl -s "https://queue.taskcluster.net/v1/pending/${provisionerId}/${workerType}" | jq '.pendingTasks')
  _echo "${workerType} pending tasks: _bold_${pending_task_count}_reset_"

  # spawn enough instances to deal with the pending task count, taking into account:
  # - the number of instances already spawned and in the pending state
  # - the configured minimum capacity for the worker type
  # - the configured maximum capacity for the worker type
  required_instance_count=0
  if [ "${pending_instance_count}" -lt "${pending_task_count}" ]; then
    (( required_instance_count = pending_task_count - pending_instance_count ))
  fi
  while (( (running_instance_count + required_instance_count) < capacity_minimum )) && (( (running_instance_count + required_instance_count) < capacity_maximum )); do
    (( required_instance_count = required_instance_count + 1 ))
  done
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
      if [[ "${SCM_LEVEL}" != "0" ]]; then
        SCCACHE_GCS_BUCKET=taskcluster-level-${SCM_LEVEL}-sccache-${region}
      fi
      # generate a random instance name which does not pre-exist
      random_name=$(basename $(mktemp ${temp_dir}/XXXXXXXXXXXXXXXXX))
      instance_name=vm-${random_name,,}
      #existing_instance_uri_list=(`gcloud compute instances list --uri`)
      #existing_instance_name_list=("${existing_instance_uri_list[@]##*/}")
      #instance_name=${names_first[$[$RANDOM % ${#names_first[@]}]]}-${names_middle[$[$RANDOM % ${#names_middle[@]}]]}-${names_last[$[$RANDOM % ${#names_last[@]}]]}
      #while [[ " ${existing_instance_name_list[@]} " =~ " ${instance_name} " ]]; do
      #  instance_name=${names_first[$[$RANDOM % ${#names_first[@]}]]}-${names_middle[$[$RANDOM % ${#names_middle[@]}]]}-${names_last[$[$RANDOM % ${#names_last[@]}]]}
      #done
      _echo "instance name: _bold_${instance_name}_reset_"
      _echo "zone name: _bold_${zone_name}_reset_"
      _echo "region: _bold_${region}_reset_"
      _echo "instance type: _bold_${instanceType}_reset_"
      _echo "worker group: _bold_${region}_reset_"
      _echo "worker type: _bold_${workerType}_reset_"

      disk_zero_size=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.boot.size' ${manifest})
      disk_zero_type=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.boot.type' ${manifest})
      disk_one_type=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.supplementary[0].type' ${manifest})

      if [[ "${workerType}" =~ ^gecko-[1-3]-b-win2012.*$ ]]; then
        pre_boot_metadata="^;^windows-startup-script-url=gs://open-cloud-config/gcloud-startup.ps1;workerType=${workerType};sourceOrg=mozilla-releng;sourceRepo=OpenCloudConfig;sourceRevision=gamma;pgpKey=${pgpKey};livelogkey=${livelogkey};livelogcrt=${livelogcrt};relengapiToken=${relengapiToken};occInstallersToken=${occInstallersToken};SCCACHE_GCS_BUCKET=${SCCACHE_GCS_BUCKET};SCCACHE_GCS_KEY=${SCCACHE_GCS_KEY}"
      elif [[ "${workerType}" =~ ^gecko-[1-3]-b-linux.*$ ]]; then
        pre_boot_metadata="^;^statelessHostname=${instance_name};relengApiToken=${relengapiToken};clientId=project/releng/docker-worker/${workerType}/production;accessToken=${accessToken};capacity=1;workerType=${workerType};provisionerId=${provisionerId};rootUrl=https://taskcluster.net;secretsPath=project/taskcluster/docker-worker:secrets"
      else
        pre_boot_metadata="^;^windows-startup-script-url=gs://open-cloud-config/gcloud-startup.ps1;workerType=${workerType};sourceOrg=mozilla-releng;sourceRepo=OpenCloudConfig;sourceRevision=gamma;pgpKey=${pgpKey};livelogkey=${livelogkey};livelogcrt=${livelogcrt};relengapiToken=${relengapiToken};occInstallersToken=${occInstallersToken}"
      fi

      # we need to check the count of running instances, however this call is rate limited and fails frequently, so we need to think of something smarter here
      #running_instance_uri_list=(`gcloud compute instances list --uri --filter "labels.worker-type:${workerType} status:RUNNING" 2> /dev/null`)
      #running_instance_count=${#running_instance_uri_list[@]}
      #if [ "${required_instance_count}" -lt "${running_instance_count}" ] && [ "${running_instance_count}" -lt "${capacity_maximum}" ]; then
      if true; then
        if [[ "${workerType}" =~ ^gecko-[1-3]-b-.*$ ]]; then
          service_account=taskcluster-level-${SCM_LEVEL}-sccache@${project_name}.iam.gserviceaccount.com
        elif [[ "${workerType}" =~ ^gecko-t-.*$ ]]; then
          service_account=gecko-test-worker@${project_name}.iam.gserviceaccount.com
        else
          service_account=${workerType}@${project_name}.iam.gserviceaccount.com
        fi
        image_project=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.image.project' ${manifest})
        image_family=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.image.family // empty' ${manifest})
        image_version=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.image.version // empty' ${manifest})
        if [ -n "${image_family}" ]; then image_selector=image-family; else image_selector=image; fi
        if [[ "${disk_one_type}" == "local-ssd" ]]; then
          disk_one_interface=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.supplementary[0].interface' ${manifest})
          gcloud compute instances create ${instance_name} \
            --description "${workerImplementation} ${workerType}" \
            --image-project ${image_project} \
            --${image_selector} ${image_family}${image_version} \
            --machine-type ${instanceType} \
            --boot-disk-size ${disk_zero_size} \
            --boot-disk-type ${disk_zero_type} \
            --boot-disk-auto-delete \
            --local-ssd interface=${disk_one_interface} \
            --scopes storage-rw \
            --service-account ${service_account} \
            --metadata "${pre_boot_metadata}" \
            --labels "worker-type=${workerType},worker-implementation=${workerImplementation},deployment-id=${deploymentId}" \
            --zone ${zone_name} \
            --preemptible
        else
          gcloud compute instances create ${instance_name} \
            --description "${workerImplementation} ${workerType}" \
            --image-project ${image_project} \
            --${image_selector} ${image_family}${image_version} \
            --machine-type ${instanceType} \
            --boot-disk-size ${disk_zero_size} \
            --boot-disk-type ${disk_zero_type} \
            --boot-disk-auto-delete \
            --scopes storage-rw \
            --service-account ${service_account} \
            --metadata "${pre_boot_metadata}" \
            --labels "worker-type=${workerType},worker-implementation=${workerImplementation},deployment-id=${deploymentId}" \
            --zone ${zone_name} \
            --preemptible
          disk_one_size=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.disks.supplementary[0].size' ${manifest})
          gcloud beta compute disks create ${instance_name}-disk-1 --type ${disk_one_type} --size ${disk_one_size} --zone ${zone_name}
          gcloud compute instances attach-disk ${instance_name} --disk ${instance_name}-disk-1 --zone ${zone_name}
          gcloud compute instances set-disk-auto-delete ${instance_name} --auto-delete --disk ${instance_name}-disk-1 --zone ${zone_name}
        fi
        publicIP=$(gcloud compute instances describe ${instance_name} --zone ${zone_name} --format json | jq -r '.networkInterfaces[0].accessConfigs[0].natIP')
        _echo "public ip: _bold_${publicIP}_reset_"
        privateIP=$(gcloud compute instances describe ${instance_name} --zone ${zone_name} --format json | jq -r '.networkInterfaces[0].networkIP')
        _echo "private ip: _bold_${privateIP}_reset_"
        instanceId=$(gcloud compute instances describe ${instance_name} --zone ${zone_name} --format json | jq -r '.id')
        _echo "instance id: _bold_${instanceId}_reset_"
        if [[ "${workerImplementation}" == "generic-worker" ]]; then
          gwConfig="`curl -s https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/gamma/userdata/Manifest/${workerType}.json | jq --arg accessToken ${accessToken} --arg livelogSecret ${livelogSecret} --arg publicIP ${publicIP} --arg privateIP ${privateIP} --arg workerId ${instance_name} --arg provisionerId ${provisionerId} --arg region ${region} --arg deploymentId ${deploymentId} --arg availabilityZone ${zone_name} --arg instanceId ${instanceId} --arg instanceType ${instanceType} -c '.ProvisionerConfiguration.userData.genericWorker.config | .accessToken = $accessToken | .livelogSecret = $livelogSecret | .publicIP = $publicIP | .privateIP = $privateIP | .workerId = $workerId | .instanceId = $instanceId | .instanceType = $instanceType | .availabilityZone = $availabilityZone | .region = $region | .provisionerId = $provisionerId | .workerGroup = $region | .deploymentId = $deploymentId' | sed 's/\"/\\\"/g'`"
          post_boot_metadata="^;^gwConfig=${gwConfig}"
        fi
        if [ -n "${post_boot_metadata}" ]; then
          gcloud compute instances add-metadata ${instance_name} --zone ${zone_name} --metadata "${post_boot_metadata}"
          unset post_boot_metadata
        fi
      fi
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
