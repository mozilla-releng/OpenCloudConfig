#!/bin/bash -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
script_name=$(basename ${0##*/} .sh)

# script config
project_name=windows-workers
provisioner_instance_name_prefix=releng-gcp-provisioner
provisioner_instance_zone=us-east1-b
provisioner_instance_machine_type=g1-small

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

# create a service account for the provisioners if it doesn't exist
provisioner_service_account_name=releng-gcp-provisioner
if [[ "$(gcloud iam service-accounts list --filter name:${provisioner_service_account_name} --format json)" == "[]" ]]; then
  gcloud iam service-accounts create ${provisioner_service_account_name} --display-name "releng gcp provisioner"
  _echo "created service account: ${provisioner_service_account_name}_reset_"
fi

# create worker service accounts if they don't exist
for worker_service_account_name in taskcluster-level-1-sccache taskcluster-level-2-sccache taskcluster-level-3-sccache relops-image-builder-gamma; do
  if [[ "$(gcloud iam service-accounts list --filter name:${worker_service_account_name} --format json)" == "[]" ]]; then
    gcloud iam service-accounts create ${worker_service_account_name} --display-name "service account for ${worker_service_account_name} instances"
    _echo "created service account: _bold_${worker_service_account_name}_reset_"
    gcloud iam service-accounts keys create /tmp/${project_name}_${worker_service_account_name}.json --iam-account ${worker_service_account_name}@${project_name}.iam.gserviceaccount.com
    _echo "created service account key: _bold_/tmp/${project_name}_${worker_service_account_name}.json_reset_"
    cat /tmp/${project_name}_${worker_service_account_name}.json | pass insert --multiline --force Mozilla/TaskCluster/gcp-service-account/${worker_service_account_name}@${project_name}
    _echo "created pass secret: _bold_Mozilla/TaskCluster/gcp-service-account/${worker_service_account_name}@${project_name}_reset_"
    rm -f /tmp/${project_name}_${worker_service_account_name}.json
    _echo "deleted service account key: _bold_/tmp/${project_name}_${worker_service_account_name}.json_reset_"
  else
    _echo "detected service account: _bold_${worker_service_account_name}_reset_"
  fi

  # grant open-cloud-config bucket viewer access to each service account so that workers can read their startup scripts
  gsutil iam ch serviceAccount:${worker_service_account_name}@${project_name}.iam.gserviceaccount.com:objectViewer gs://open-cloud-config/
  _echo "added viewer access for: _bold_${worker_service_account_name}@${project_name}_reset_ to bucket: _bold_gs://open-cloud-config/_reset_"

  if [[ "${worker_service_account_name}" == "relops-image-builder"* ]]; then
    # grant windows-ami-builder bucket admin access to relops-image-builder service accounts so that workers can read and write image builder resources
    gsutil iam ch serviceAccount:${worker_service_account_name}@${project_name}.iam.gserviceaccount.com:objectAdmin gs://windows-ami-builder/
    _echo "added admin access for: _bold_${worker_service_account_name}@${project_name}_reset_ to bucket: _bold_gs://windows-ami-builder/_reset_"
  fi

  # grant role allowing assignment of service accounts to provisioned instances
  # note that the user running this script needs the role: roles/iam.serviceAccountUser. eg:
  # - gcloud iam service-accounts add-iam-policy-binding releng-gcp-provisioner@windows-workers.iam.gserviceaccount.com --member user:someuser@mozilla.com --role roles/iam.serviceAccountUser
  # - gcloud iam service-accounts add-iam-policy-binding ${provisioner_service_account_name}@${project_name}.iam.gserviceaccount.com --member user:${user}@mozilla.com --role roles/iam.serviceAccountUser
  gcloud iam service-accounts add-iam-policy-binding ${worker_service_account_name}@${project_name}.iam.gserviceaccount.com --member serviceAccount:${provisioner_service_account_name}@${project_name}.iam.gserviceaccount.com --role roles/iam.serviceAccountUser
done

# grant role allowing management of compute instances
gcloud projects add-iam-policy-binding ${project_name} --member serviceAccount:${provisioner_service_account_name}@${project_name}.iam.gserviceaccount.com --role roles/compute.admin

# grant role allowing management of occ bucket
gsutil iam ch serviceAccount:${provisioner_service_account_name}@${project_name}.iam.gserviceaccount.com:objectAdmin gs://open-cloud-config/
#gcloud projects add-iam-policy-binding windows-workers --member serviceAccount:releng-gcp-provisioner@windows-workers.iam.gserviceaccount.com --role roles/compute.admin
#gcloud projects add-iam-policy-binding ${project_name} --member serviceAccount:${provisioner_service_account_name}@${project_name}.iam.gserviceaccount.com --role roles/iam.serviceAccountUser

# generate a new provisioner instance name which does not pre-exist
existing_provisioner_instance_uri_list=(`gcloud compute instances list --uri`)
existing_provisioner_instance_name_list=("${existing_provisioner_instance_uri_list[@]##*/}")
provisioner_instance_number=0
provisioner_instance_name=${provisioner_instance_name_prefix}-${provisioner_instance_number}
while [[ " ${existing_provisioner_instance_name_list[@]} " =~ " ${provisioner_instance_name} " ]]; do
  (( provisioner_instance_number = provisioner_instance_number + 1 ))
  provisioner_instance_name=${provisioner_instance_name_prefix}-${provisioner_instance_number}
done

# provisioning secrets
livelogSecret=`pass Mozilla/TaskCluster/livelogSecret`
livelogcrt=`pass Mozilla/TaskCluster/livelogCert`
livelogkey=`pass Mozilla/TaskCluster/livelogKey`
pgpKey=`pass Mozilla/OpenCloudConfig/rootGpgKey`
relengapiToken=`pass Mozilla/OpenCloudConfig/tooltool-relengapi-tok`
occInstallersToken=`pass Mozilla/OpenCloudConfig/tooltool-occ-installers-tok`
SCCACHE_GCS_KEY=("")
for scm_level in {1..3}; do
  SCCACHE_GCS_KEY[${scm_level}]=`pass Mozilla/TaskCluster/gcp-service-account/taskcluster-level-${scm_level}-sccache@${project_name}`
done


# update the provisioner startup script (copy from repo to gs bucket)
gsutil cp ${script_dir}/gcloud-init-provisioner.sh gs://open-cloud-config/
_echo "provisioner startup script updated in bucket_reset_"

# add worker-type specific access tokens to secrets metadata
accessTokens=()
ARRAY+=('foo')
ARRAY+=('bar')
for manifest in $(ls $HOME/git/mozilla-releng/OpenCloudConfig/userdata/Manifest/*-gamma.json); do
  workerType=$(basename ${manifest##*/} .json)
  workerImplementation=$(jq -r '.ProvisionerConfiguration.releng_gcp_provisioner.worker_implementation' ${manifest})
  accessTokens+=("access-token-${workerType}=`pass Mozilla/TaskCluster/project/releng/${workerImplementation}/${workerType}/production`")
done
function join_by { local IFS="$1"; shift; echo "$*"; }
metadataAccessTokens=`join_by ';' "${accessTokens[@]}"`

# spawn a provisioner with startup script and secrets in metadata
gcloud compute instances create ${provisioner_instance_name} \
  --zone ${provisioner_instance_zone} \
  --machine-type ${provisioner_instance_machine_type} \
  --scopes compute-rw,service-management,storage-rw \
  --service-account ${provisioner_service_account_name}@${project_name}.iam.gserviceaccount.com \
  --metadata "^;^startup-script-url=gs://open-cloud-config/gcloud-init-provisioner.sh;livelogSecret=${livelogSecret};livelogcrt=${livelogcrt};livelogkey=${livelogkey};pgpKey=${pgpKey};relengapiToken=${relengapiToken};occInstallersToken=${occInstallersToken};SCCACHE_GCS_KEY_1=${SCCACHE_GCS_KEY[1]};SCCACHE_GCS_KEY_2=${SCCACHE_GCS_KEY[2]};SCCACHE_GCS_KEY_3=${SCCACHE_GCS_KEY[3]};${metadataAccessTokens}"
_echo "provisioner: ${provisioner_instance_name} created as ${provisioner_instance_machine_type} in ${provisioner_instance_zone}_reset_"
