#!/bin/bash -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
script_name=$(basename ${0##*/} .sh)

provisionerId=releng-hardware

for manifest in $(ls ${script_dir}/../userdata/Manifest/*-gamma.json); do
  workerType=$(basename ${manifest##*/} .json)
  echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")]$(tput sgr0) worker type: $(tput bold)${workerType}$(tput sgr0)"
  # delete instances that have never taken a task
  for instance in $(curl -s "https://queue.taskcluster.net/v1/provisioners/${provisionerId}/worker-types/${workerType}/workers" | jq -r '.workers[] | select(.latestTask == null) | @base64'); do
    _jq() {
      echo ${instance} | base64 --decode | jq -r ${1}
    }
    zoneUrl=$(gcloud compute instances list --filter="name:$(_jq '.workerId') AND zone~$(_jq '.workerGroup')" --format=json | jq -r '.[0].zone')
    zone=${zoneUrl##*/}
    if [ -n "${zoneUrl}" ] && [ -n "${zone}" ] && [[ "${zone}" != "null" ]] && gcloud compute instances delete $(_jq '.workerId') --zone ${zone} --delete-disks all --quiet; then
      echo "$(tput dim)[${script_name} $(date --utc +"%F %T.%3NZ")]$(tput sgr0) deleted: $(tput bold)${zone}/$(_jq '.workerId')$(tput sgr0)"
    fi
  done
done