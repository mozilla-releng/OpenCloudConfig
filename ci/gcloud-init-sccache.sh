#!/bin/bash -e

project_name=windows-workers

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

# create service accounts for each scm level
for scm_level in {1..3}; do
  service_account_name=taskcluster-level-${scm_level}-sccache
  if [[ "$(gcloud iam service-accounts list --filter name:${service_account_name} --format json)" == "[]" ]]; then
    gcloud iam service-accounts create ${service_account_name} --display-name "sccache access for scm level ${scm_level}"
    _echo "created service account: _bold_${service_account_name}_reset_"
    gcloud iam service-accounts keys create /tmp/${project_name}_${service_account_name}.json --iam-account ${service_account_name}@${project_name}.iam.gserviceaccount.com
    _echo "created service account key: _bold_/tmp/${project_name}_${service_account_name}.json_reset_"
    cat /tmp/${project_name}_${service_account_name}.json | pass insert --multiline --force Mozilla/TaskCluster/gcp-service-account/${service_account_name}@${project_name}
    _echo "created pass secret: _bold_Mozilla/TaskCluster/gcp-service-account/${service_account_name}@${project_name}_reset_"
    rm -f /tmp/${project_name}_${service_account_name}.json
    _echo "deleted service account key: _bold_/tmp/${project_name}_${service_account_name}.json_reset_"
  fi
done

# create grant open-cloud-config bucket viewer access to each service account so that workers can read their startup scripts
for scm_level in {1..3}; do
  service_account_name=taskcluster-level-${scm_level}-sccache
  gsutil iam ch serviceAccount:${service_account_name}@${project_name}.iam.gserviceaccount.com:objectViewer gs://open-cloud-config/
  _echo "added viewer access for: _bold_${service_account_name}@${project_name}_reset_ to bucket: _bold_gs://open-cloud-config/_reset_"
done

# get a list of compute regions
region_uri_list=(`gcloud compute regions list --uri`)
region_name_list=("${region_uri_list[@]##*/}")

# create regional sccache buckets for each scm level and grant bucket access to the appropriate service account for that level
for region_name in "${region_name_list[@]}"; do
  for scm_level in {1..3}; do
    service_account_name=taskcluster-level-${scm_level}-sccache
    if gsutil du -s gs://${service_account_name}-${region_name}/; then
      _echo "detected bucket: _bold_gs://${service_account_name}-${region_name}/_reset_"
    else
      gsutil mb -p ${project_name} -c regional -l ${region_name} gs://${service_account_name}-${region_name}/
      _echo "created bucket: _bold_gs://${service_account_name}-${region_name}/_reset_"
      gsutil iam ch serviceAccount:${service_account_name}@${project_name}.iam.gserviceaccount.com:objectAdmin gs://${service_account_name}-${region_name}/
      _echo "added admin access for: _bold_${service_account_name}@${project_name}_reset_ to bucket: _bold_gs://${service_account_name}-${region_name}/_reset_"
    fi
  done
done