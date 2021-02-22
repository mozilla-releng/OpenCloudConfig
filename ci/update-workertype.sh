#!/bin/bash -e

shopt -s extglob

if [ "${#}" -lt 1 ]; then
  echo "workertype argument missing; usage: ./update-workertype.sh workertype" >&2
  exit 64
fi
mkdir -p ./instance-logs
touch ./instance-logs/no-instance-logs
tc_worker_type="${1}"

manifest=./OpenCloudConfig/userdata/Manifest/${tc_worker_type}.json
# todo: find a way to validate if something is already in tooltool (now that hawk headers are required)
# validate that manifest components, which contain a sha512 hash, have a corresponding tooltool artifact
#secrets_url="taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig:updatetooltoolrepo"
#curl -s -N ${secrets_url} | jq '.secret.tooltool | del(.upload)' > ./.tooltool.token
#echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] tooltool token downloaded"
#echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] validating Manifest ${manifest}"
#for ComponentType in ExeInstall MsiInstall MsuInstall ZipInstall; do
#  jq --arg componentType ${ComponentType} -r '.Components[] | select(.ComponentType == $componentType and (.sha512 != "" and .sha512 != null)) | .sha512' ${manifest} | while read sha512; do
#    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] validating ${ComponentType} ${sha512}"
#    tt_url="https://tooltool.mozilla-releng.net/sha512/${sha512}"
#    if curl --header "Authorization: Bearer $(cat ./.tooltool.token)" --output /dev/null --silent --head --fail ${tt_url}; then
#      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ${sha512} found in tooltool: ${tt_url}"
#    else
#      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ${sha512} missing from tooltool: ${tt_url}"
#      exit 63
#    fi
#  done
#done

# get some secrets from tc
secrets_url=taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig
TASKCLUSTER_AWS_ACCESS_KEY=$(curl -s -N ${secrets_url}:updateworkertype | jq -r '.secret.aws.access')
TASKCLUSTER_AWS_SECRET_KEY=$(curl -s -N ${secrets_url}:updateworkertype | jq -r '.secret.aws.secret')
: ${TASKCLUSTER_AWS_ACCESS_KEY:?"TASKCLUSTER_AWS_ACCESS_KEY is not set"}
: ${TASKCLUSTER_AWS_SECRET_KEY:?"TASKCLUSTER_AWS_SECRET_KEY is not set"}
export AWS_ACCESS_KEY_ID=${TASKCLUSTER_AWS_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${TASKCLUSTER_AWS_SECRET_KEY}

aws_region=${aws_region:='us-west-2'}
AWS_DEFAULT_REGION=${aws_region}
ami_copy_regions=('eu-central-1' 'us-east-1' 'us-east-2' 'us-west-1')

aws_key_name="mozilla-taskcluster-worker-${tc_worker_type}"
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] aws_key_name: ${aws_key_name}"

echo "{\"secret\":{\"latest\":{\"timestamp\":\"\",\"git-sha\":\"${GITHUB_HEAD_SHA:0:12}\"}}}" | jq '.' > ./workertype-secrets.json

commit_message=$(curl --silent https://api.github.com/repos/mozilla-releng/OpenCloudConfig/git/commits/${GITHUB_HEAD_SHA} | jq -r '.message')
echo "DEBUG: parsing commit message for deployment instructions..."
if [[ $commit_message == *"nodeploy:"* ]]; then
  no_deploy_list=$([[ ${commit_message} =~ nodeploy:\s+?([^;]*) ]] && echo "${BASH_REMATCH[1]}")
  if [[ " ${no_deploy_list[*]} " == *" ${tc_worker_type} "* ]]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment skipped due to presence of ${tc_worker_type} in commit message no-deploy list (${no_deploy_list[*]})"
    exit
  fi
elif [[ $commit_message == *"deploy: all"* ]]; then
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deploying ${tc_worker_type} as part of 'deploy: all'"
elif [[ $commit_message == *"deploy: alpha"* ]] && ([[ "${tc_worker_type}" == *"-alpha" ]] || [[ "${tc_worker_type}" == *"-gpu-a" ]]); then
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deploying ${tc_worker_type} as part of 'deploy: alpha'"
elif [[ $commit_message == *"deploy: beta"* ]] && ([[ "${tc_worker_type}" == *"-beta" ]] || [[ "${tc_worker_type}" == *"-gpu-b" ]]); then
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deploying ${tc_worker_type} as part of 'deploy: beta'"
elif [[ $commit_message == *"deploy: mpd" ]] && [[ "${tc_worker_type}" == "mpd"* ]]; then
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deploying ${tc_worker_type} as part of 'deploy: mpd'"
elif [[ $commit_message == *"deploy:"* ]]; then
  deploy_list=$([[ ${commit_message} =~ deploy:\s+?([^;]*) ]] && echo "${BASH_REMATCH[1]}")
  if [[ " ${deploy_list[*]} " != *" ${tc_worker_type} "* ]]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment skipped due to absence of ${tc_worker_type} in commit message deploy list (${deploy_list[*]})"
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] following is a list of all available ${workerType} amis:"
    echo "---" > ./ami-latest.yml
    echo "---" | tee ./ami-list.yml
    for region in ${ami_copy_regions[@]} ${aws_region}; do
      regional_ami_index=0
      echo "${region}:" | tee -a ./ami-list.yml
        aws ec2 describe-images --region ${region} --owners self --filters "Name=name,Values=${workerType} *" | jq -r '[ .Images[] | { ImageId, Name, Description, CreationDate, WorkerType: (.Name | split(" "))[0], OccRevision: (.Name | sub(" version "; " ") | split(" "))[1], BuildTask: (.Name | sub(" version "; " ") | split(" "))[2] } ] | sort_by(.CreationDate) | reverse | .[] | @base64' | while read item; do
          _jq_decode() {
            echo ${item} | base64 --decode | jq -r ${1}
          }
          if [[ "$(_jq_decode '.WorkerType')" == "${tc_worker_type}" ]]; then
            ami_id=$(_jq_decode '.ImageId')
            echo "- id: ${ami_id}" | tee -a ./ami-list.yml
            echo "  name: $(_jq_decode '.Name')" | tee -a ./ami-list.yml
            echo "  description: \"$(_jq_decode '.Description')\"" | tee -a ./ami-list.yml
            echo "  created: $(_jq_decode '.CreationDate')" | tee -a ./ami-list.yml
            echo "  revision: $(_jq_decode '.OccRevision')" | tee -a ./ami-list.yml
            echo "  build: $(_jq_decode '.BuildTask')" | tee -a ./ami-list.yml
            if (( regional_ami_index == 0 )); then
              echo "${region}: ${ami_id}" >> ./ami-latest.yml
            fi
            regional_ami_index=$((regional_ami_index+1))
          fi
      done
    done
    yq '.' ./ami-list.yml > ./ami-list.json
    yq '.' ./ami-latest.yml > ./ami-latest.json
    exit
  fi
else
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment skipped due to absent deploy instruction in commit message (${commit_message})"
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] following is a list of all available ${workerType} amis:"
  echo "---" > ./ami-latest.yml
  echo "---" | tee ./ami-list.yml
  for region in ${ami_copy_regions[@]} ${aws_region}; do
    regional_ami_index=0
    echo "${region}:" | tee -a ./ami-list.yml
      aws ec2 describe-images --region ${region} --owners self --filters "Name=name,Values=${workerType} *" | jq -r '[ .Images[] | { ImageId, Name, Description, CreationDate, WorkerType: (.Name | split(" "))[0], OccRevision: (.Name | sub(" version "; " ") | split(" "))[1], BuildTask: (.Name | sub(" version "; " ") | split(" "))[2] } ] | sort_by(.CreationDate) | reverse | .[] | @base64' | while read item; do
        _jq_decode() {
          echo ${item} | base64 --decode | jq -r ${1}
        }
        if [[ "$(_jq_decode '.WorkerType')" == "${tc_worker_type}" ]]; then
          ami_id=$(_jq_decode '.ImageId')
          echo "- id: ${ami_id}" | tee -a ./ami-list.yml
          echo "  name: $(_jq_decode '.Name')" | tee -a ./ami-list.yml
          echo "  description: \"$(_jq_decode '.Description')\"" | tee -a ./ami-list.yml
          echo "  created: $(_jq_decode '.CreationDate')" | tee -a ./ami-list.yml
          echo "  revision: $(_jq_decode '.OccRevision')" | tee -a ./ami-list.yml
          echo "  build: $(_jq_decode '.BuildTask')" | tee -a ./ami-list.yml
          if (( regional_ami_index == 0 )); then
            echo "${region}: ${ami_id}" >> ./ami-latest.yml
          fi
          regional_ami_index=$((regional_ami_index+1))
        fi
    done
  done
  yq '.' ./ami-list.yml > ./ami-list.json
  yq '.' ./ami-latest.yml > ./ami-latest.json
  exit
fi

case "${tc_worker_type}" in
  gecko-t-win7-32*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='gecko-t-win7-32-kb4499175-20190516082500'}
    echo "DEBUG: searching for latest base ami for: ${tc_worker_type}, using search term: ${aws_base_ami_search_term}"
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko test worker for Windows 7 32 bit; worker-type: ${tc_worker_type}, source: ${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}, deploy: https://tools.taskcluster.net/tasks/${TASK_ID}"
    root_username=root
    ;;
  gecko-t-win10-64-alpha|gecko-t-win10-64-gpu-a)
    aws_base_ami_search_term=${aws_base_ami_search_term:='Windows_10_Professional_1903_18362_239_en-US_x64-VAC-*'}
    echo "DEBUG: searching for latest base ami for: ${tc_worker_type}, using search term: ${aws_base_ami_search_term}"
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko tester for Windows 10 64 bit; worker-type: ${tc_worker_type}, source: ${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}, deploy: https://tools.taskcluster.net/tasks/${TASK_ID}"
    root_username=Administrator
    ;;
  gecko-t-win10-64*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='Windows_10_Enterprise_1803_17134_285_en-US_x64_MBR-VAC-*'}
    echo "DEBUG: searching for latest base ami for: ${tc_worker_type}, using search term: ${aws_base_ami_search_term}"
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko tester for Windows 10 64 bit; worker-type: ${tc_worker_type}, source: ${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}, deploy: https://tools.taskcluster.net/tasks/${TASK_ID}"
    root_username=Administrator
    ;;
  mpd001-[13]-b-win2012|gecko-[123]-b-win2012*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='gecko-b-win2012-ena-base-*'}
    echo "DEBUG: searching for latest base ami for: ${tc_worker_type}, using search term: ${aws_base_ami_search_term}"
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko builder for Windows; worker-type: ${tc_worker_type}, source: ${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}, deploy: https://tools.taskcluster.net/tasks/${TASK_ID}"
    root_username=Administrator
    ;;
  relops-image-builder)
    aws_base_ami_search_term=${aws_base_ami_search_term:='Windows_Server-2019-English-Full-Base-*'}
    echo "DEBUG: searching for latest base ami for: ${tc_worker_type}, using search term: ${aws_base_ami_search_term}"
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners amazon --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="RelOps image builder for Windows; worker-type: ${tc_worker_type}, source: ${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}, deploy: https://tools.taskcluster.net/tasks/${TASK_ID}"
    root_username=Administrator
    ;;
  *)
    echo "ERROR: no base ami search term configured for: ${tc_worker_type}"
    exit 67
    ;;
esac
if [ -z "${aws_base_ami_id}" ]; then
  echo "ERROR: failed to find a suitable base ami matching: '${aws_base_ami_search_term}'"
  exit 69
fi
echo "INFO: selected: ${aws_base_ami_id}, for: ${tc_worker_type}, using search term: ${aws_base_ami_search_term}"
aws ec2 describe-images --region ${aws_region} --image-ids ${aws_base_ami_id}

echo "DEBUG: parsing provisioner configuration (instance types) from ${manifest}..."
provisioner_configuration_instance_types=$(jq -c '.ProvisionerConfiguration.instanceTypes' ${manifest})
echo "DEBUG: parsing provisioner configuration (user data) from ${manifest}..."
provisioner_configuration_userdata=$(jq -c '.ProvisionerConfiguration.userData' ${manifest})
echo "DEBUG: parsing provisioner configuration (launch spec / block device mappings) from ${manifest}..."
snapshot_block_device_mappings=$(jq -c '.ProvisionerConfiguration.instanceTypes[0].launchSpec.BlockDeviceMappings' ${manifest})
echo "DEBUG: parsing provisioner configuration (first instance type) from ${manifest}..."
snapshot_aws_instance_type=$(jq -c -r '.ProvisionerConfiguration.instanceTypes[0].instanceType' ${manifest})

echo "DEBUG: constructing userdata..."
userdata=$(cat ./OpenCloudConfig/ci/userdata)
SOURCE_ORG_REPO=${GITHUB_HEAD_REPO_URL:19}
SOURCE_ORG_REPO=${SOURCE_ORG_REPO/.git/}
SOURCE_ORG=${SOURCE_ORG_REPO/\/$GITHUB_HEAD_REPO_NAME/}

echo "DEBUG: generating instance passwords..."
root_password="$(pwgen -1sBync 16)"
root_password="${root_password//[<>\"\'\`\\\/]/_}"
worker_password="$(pwgen -1sBync 16)"
worker_password="${worker_password//[<>\"\'\`\\\/]/_}"
userdata=${userdata//ROOT_PASSWORD_TOKEN/$root_password}
userdata=${userdata//WORKER_PASSWORD_TOKEN/$worker_password}
userdata=${userdata//ROOT_GPG_KEY_TOKEN/$(curl -s -N ${secrets_url}:updateworkertype | jq -r '.secret.rootGpgKey')}

# if commit message includes a line like: "(alpha-source|beta-source): custom-gh-username-or-org custom-gh-repo custom-gh-ref-or-rev"
# and worker type is an alpha or beta, inject userdata with custom org, repo and ref data so that beta amis are built with
# OCC urls like: github.com/custom-gh-username-or-org/custom-gh-repo/custom-gh-ref-or-rev/...
echo "DEBUG: parsing commit message for source instructions..."
if [[ $commit_message == *"alpha-source:"* ]] && ([[ "$tc_worker_type" == *"-gpu-a" ]] || [[ "$tc_worker_type" == *"-alpha" ]]); then
  alpha_source=( $([[ ${commit_message} =~ alpha-source:\s+?([^;]*) ]] && echo "${BASH_REMATCH[1]}") )
  userdata=${userdata//SOURCE_ORG_TOKEN/${alpha_source[0]}}
  userdata=${userdata//SOURCE_REPO_TOKEN/${alpha_source[1]}}
  userdata=${userdata//SOURCE_REV_TOKEN/${alpha_source[2]}}
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment source set to: ${alpha_source[0]}/${alpha_source[1]}/${alpha_source[2]}"
  occ_manifest="https://github.com/${alpha_source[0]}/${alpha_source[1]}/blob/${alpha_source[2]}/userdata/Manifest/${tc_worker_type}.json"
elif [[ $commit_message == *"beta-source:"* ]] && ([[ "$tc_worker_type" == *"-gpu-b" ]] || [[ "$tc_worker_type" == *"-beta" ]]); then
  beta_source=( $([[ ${commit_message} =~ beta-source:\s+?([^;]*) ]] && echo "${BASH_REMATCH[1]}") )
  userdata=${userdata//SOURCE_ORG_TOKEN/${beta_source[0]}}
  userdata=${userdata//SOURCE_REPO_TOKEN/${beta_source[1]}}
  userdata=${userdata//SOURCE_REV_TOKEN/${beta_source[2]}}
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment source set to: ${beta_source[0]}/${beta_source[1]}/${beta_source[2]}"
  occ_manifest="https://github.com/${beta_source[0]}/${beta_source[1]}/blob/${beta_source[2]}/userdata/Manifest/${tc_worker_type}.json"
else
  userdata=${userdata//SOURCE_ORG_TOKEN/${SOURCE_ORG}}
  userdata=${userdata//SOURCE_REPO_TOKEN/${GITHUB_HEAD_REPO_NAME}}
  userdata=${userdata//SOURCE_REV_TOKEN/${GITHUB_HEAD_SHA}}
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment source set to: ${SOURCE_ORG}/${GITHUB_HEAD_REPO_NAME}/${GITHUB_HEAD_SHA}"
  occ_manifest="https://github.com/${SOURCE_ORG}/${GITHUB_HEAD_REPO_NAME}/blob/${GITHUB_HEAD_SHA}/userdata/Manifest/${tc_worker_type}.json"
fi
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] occ manifest set to: ${occ_manifest}"

short_sha=${GITHUB_HEAD_SHA:0:12}
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] git sha: ${short_sha} used for aws client token"

#curl --silent http://taskcluster/aws-provisioner/v1/worker-type/${tc_worker_type} | jq '.' > ./${tc_worker_type}-pre.json
#cat ./${tc_worker_type}-pre.json | jq --arg occmanifest $occ_manifest --arg deploydate "$(date --utc +"%F %T.%3NZ")" --arg deploymentId ${short_sha} --argjson instanceTypes ${provisioner_configuration_instance_types} --argjson userData $provisioner_configuration_userdata -c 'del(.workerType, .lastModified, .userData, .secrets.files, .secrets."generic-worker") | .instanceTypes = $instanceTypes | .userData = $userData | .userData.genericWorker.config.deploymentId = $deploymentId | .userData.genericWorker.config.workerTypeMetadata."machine-setup".manifest = $occmanifest | .userData.genericWorker.config.workerTypeMetadata."machine-setup"."ami-created" = $deploydate' > ./${tc_worker_type}.json
#echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] active amis (pre-update): $(cat ./${tc_worker_type}.json | jq -c '[.regions[] | {region: .region, ami: .launchSpec.ImageId}]')"
#echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] latest base ami for: ${aws_base_ami_search_term}, in region: ${aws_region}, is: ${aws_base_ami_id} (https://${aws_region}.console.aws.amazon.com/ec2/v2/home?region=${aws_region}#Images:visibility=owned-by-me;imageId=${aws_base_ami_id})"

# create instance, apply user-data, filter output, get instance id, tag instance, wait for shutdown
while [ -z "$aws_instance_id" ]; do
  aws_instance_id="$(aws ec2 run-instances --region ${aws_region} --image-id "${aws_base_ami_id}" --key-name ${aws_key_name} --security-group-ids "sg-3bd7bf41" --subnet-id "subnet-f94cb29f" --user-data "${userdata}" --instance-type ${snapshot_aws_instance_type} --block-device-mappings "${snapshot_block_device_mappings}" --instance-initiated-shutdown-behavior stop --client-token "${short_sha}-${TASK_ID}/${RUN_ID}" | sed -n 's/^ *"InstanceId": "\(.*\)", */\1/p')"
  if [ -z "$aws_instance_id" ]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] https://${aws_region}.console.aws.amazon.com/ec2/v2/home?region=${aws_region}#Instances:instanceType='${snapshot_aws_instance_type}';lifecycle=normal;instanceState=!stopped,!terminated;sort=desc:launchTime"
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] create instance failed. retrying..."
  fi
done
log_min_time=$(date --utc +"%F %T UTC")
until `aws ec2 create-tags --region ${aws_region} --resources "${aws_instance_id}" --tags "Key=WorkerType,Value=golden-${tc_worker_type}" "Key=source,Value=${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}" "Key=build,Value=https://tools.taskcluster.net/tasks/${TASK_ID}" >/dev/null 2>&1`; do
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for instance instantiation"
done
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] instance: ${aws_instance_id} instantiated and tagged: WorkerType=golden-${tc_worker_type} (https://${aws_region}.console.aws.amazon.com/ec2/v2/home?region=${aws_region}#Instances:instanceId=${aws_instance_id})"
sleep 30 # give aws 30 seconds to start the instance
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] userdata logging to: https://papertrailapp.com/groups/2488493/events?q=${aws_instance_id}"
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] userdata logging to: https://papertrailapp.com/systems/${aws_instance_id}.${tc_worker_type}.usw2.mozilla.com/events"
aws_instance_public_ip="$(aws ec2 describe-instances --region ${aws_region} --instance-id "${aws_instance_id}" --query 'Reservations[*].Instances[*].NetworkInterfaces[*].Association.PublicIp' --output text)"
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] instance public ip: ${aws_instance_public_ip}"

# wait for instance stopped state
until `aws ec2 wait instance-stopped --region ${aws_region} --instance-ids "${aws_instance_id}" >/dev/null 2>&1`; do
  instance_state=$(aws ec2 describe-instances --region ${aws_region} --instance-id ${aws_instance_id} --query 'Reservations[*].Instances[*].State.Name' --output text)
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for instance to shut down. current state: ${instance_state}"
  if [ "${instance_state}" == "terminated" ]; then
    exit 68
  fi
done

# create ami, get ami id, tag ami, wait for ami availability
while [ -z "$aws_ami_id" ]; do
  # if we are dynamically adding the y: and z: ebs volume, detach and discard it before capturing ami.
  if [[ $snapshot_block_device_mappings == *"/dev/sdb"* ]]; then
    dev_sdb_volume_id=$(aws ec2 describe-instances --region ${aws_region} --instance-id ${aws_instance_id} --query 'Reservations[*].Instances[*].BlockDeviceMappings[1].Ebs.VolumeId' --output text)
    if [[ $snapshot_block_device_mappings == *"/dev/sdc"* ]]; then
      dev_sdc_volume_id=$(aws ec2 describe-instances --region ${aws_region} --instance-id ${aws_instance_id} --query 'Reservations[*].Instances[*].BlockDeviceMappings[2].Ebs.VolumeId' --output text)
      aws ec2 detach-volume --region ${aws_region} --instance-id ${aws_instance_id} --device /dev/sdc --volume-id ${dev_sdc_volume_id}
      until `aws ec2 wait volume-available --region ${aws_region} --volume-ids "${dev_sdc_volume_id}" >/dev/null 2>&1`; do
        echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdc_volume_id} detaching..."
      done
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdc_volume_id} detached from ${aws_instance_id} /dev/sdc"
      aws ec2 delete-volume --region ${aws_region} --volume-id ${dev_sdc_volume_id}
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdc_volume_id} deleted"
    fi
    aws ec2 detach-volume --region ${aws_region} --instance-id ${aws_instance_id} --device /dev/sdb --volume-id ${dev_sdb_volume_id}
    until `aws ec2 wait volume-available --region ${aws_region} --volume-ids "${dev_sdb_volume_id}" >/dev/null 2>&1`; do
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdb_volume_id} detaching..."
    done
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdb_volume_id} detached from ${aws_instance_id} /dev/sdb"
    aws ec2 delete-volume --region ${aws_region} --volume-id ${dev_sdb_volume_id}
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdb_volume_id} deleted"
  fi
  if [[ $snapshot_block_device_mappings == *"xvdf"* ]]; then
    xvdf_volume_id=$(aws ec2 describe-instances --region ${aws_region} --instance-id ${aws_instance_id} --query 'Reservations[*].Instances[*].BlockDeviceMappings[1].Ebs.VolumeId' --output text)
    aws ec2 detach-volume --region ${aws_region} --instance-id ${aws_instance_id} --device xvdf --volume-id ${xvdf_volume_id}
    until `aws ec2 wait volume-available --region ${aws_region} --volume-ids "${xvdf_volume_id}" >/dev/null 2>&1`; do
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${xvdf_volume_id} detaching..."
    done
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${xvdf_volume_id} detached from ${aws_instance_id} xvdf"
    aws ec2 delete-volume --region ${aws_region} --volume-id ${xvdf_volume_id}
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${xvdf_volume_id} deleted"
  fi
  aws_ami_id=`aws ec2 create-image --region ${aws_region} --instance-id ${aws_instance_id} --name "${tc_worker_type} ${short_sha} ${TASK_ID}/${RUN_ID}" --description "${ami_description}" | sed -n 's/^ *"ImageId": *"\(.*\)" *$/\1/p'`
  if [ -z "$aws_ami_id" ]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] create image failed. retrying..."
  fi
done
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ami: ${aws_ami_id} creation in progress: https://${aws_region}.console.aws.amazon.com/ec2/v2/home?region=${aws_region}#Images:visibility=owned-by-me;search=${aws_ami_id}"
aws ec2 create-tags --region ${aws_region} --resources "${aws_ami_id}" --tags "Key=WorkerType,Value=${tc_worker_type}" "Key=source,Value=${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}" "Key=build,Value=https://tools.taskcluster.net/tasks/${TASK_ID}"
sleep 30
until `aws ec2 wait image-available --region ${aws_region} --image-ids "${aws_ami_id}" >/dev/null 2>&1`; do
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for ami availability (${aws_region} ${aws_ami_id})"
done
#cat ./${tc_worker_type}.json | jq --arg ec2region $aws_region --arg amiid $aws_ami_id -c '(.regions[] | select(.region == $ec2region) | .launchSpec.ImageId) = $amiid' > ./.${tc_worker_type}.json && rm ./${tc_worker_type}.json && mv ./.${tc_worker_type}.json ./${tc_worker_type}.json
cat ./workertype-secrets.json | jq --arg ec2region $aws_region --arg amiid $aws_ami_id -c '.secret.latest.amis |= . + [{region:$ec2region,"ami-id":$amiid}]' > ./.workertype-secrets.json && rm ./workertype-secrets.json && mv ./.workertype-secrets.json ./workertype-secrets.json

# purge all but 10 newest workertype amis in region
aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=name,Values=${tc_worker_type} *" | jq '[ .Images[] | { ImageId, CreationDate, SnapshotId: .BlockDeviceMappings[0].Ebs.SnapshotId } ] | sort_by(.CreationDate) [ 0 : -10 ]' > ./delete-queue-${aws_region}.json
jq '.|keys[]' ./delete-queue-${aws_region}.json | while read i; do
  old_ami=$(jq -r ".[$i].ImageId" ./delete-queue-${aws_region}.json)
  old_snap=$(jq -r ".[$i].SnapshotId" ./delete-queue-${aws_region}.json)
  old_cd=$(jq ".[$i].CreationDate" ./delete-queue-${aws_region}.json)
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deregistering old ami: ${old_ami}, created: ${old_cd}, in ${aws_region}"
  aws ec2 deregister-image --region ${aws_region} --image-id ${old_ami} || true
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deleting old snapshot: ${old_snap}, for ami: ${old_ami}"
  aws ec2 delete-snapshot --region ${aws_region} --snapshot-id ${old_snap} || true
done

# purge all but newest workertype golden instances (only needed in the base region where goldens are instantiated)
aws ec2 describe-instances --region ${aws_region} --filters Name=tag-key,Values=WorkerType "Name=tag-value,Values=golden-${tc_worker_type}" | jq '[ .Reservations[].Instances[] | { InstanceId, LaunchTime } ] | sort_by(.LaunchTime) [ 0 : -1 ]' > ./instance-delete-queue-${aws_region}.json
jq '.|keys[]' ./instance-delete-queue-${aws_region}.json | while read i; do
  old_instance=$(jq -r ".[$i].InstanceId" ./instance-delete-queue-${aws_region}.json)
  old_lt=$(jq ".[$i].LaunchTime" ./instance-delete-queue-${aws_region}.json)
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] terminating old instance: ${old_instance}, launched: ${old_lt}, in ${aws_region}"
  aws ec2 terminate-instances --region ${aws_region} --instance-ids ${old_instance} || true
done

# copy ami to each region, get copied ami id, tag copied ami
declare -A copied_regional_ami_ids
for region in ${ami_copy_regions[@]}; do
  aws_copied_ami_id=`aws ec2 copy-image --region ${region} --source-region ${aws_region} --source-image-id ${aws_ami_id} --name "${tc_worker_type} ${short_sha} ${TASK_ID}/${RUN_ID}" --description "${ami_description}" | sed -n 's/^ *"ImageId": *"\(.*\)" *$/\1/p'`
  copied_regional_ami_ids+=([${region}]=${aws_copied_ami_id})
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ami: ${aws_region} ${aws_ami_id} copy to ${region} ${aws_copied_ami_id} in progress: https://${region}.console.aws.amazon.com/ec2/v2/home?region=${region}#Images:visibility=owned-by-me;search=${aws_copied_ami_id}"
  aws ec2 create-tags --region ${region} --resources "${aws_copied_ami_id}" --tags "Key=WorkerType,Value=${tc_worker_type}" "Key=source,Value=${GITHUB_HEAD_REPO_URL::-4}/commit/${GITHUB_HEAD_SHA:0:7}" "Key=build,Value=https://tools.taskcluster.net/tasks/${TASK_ID}"
  #cat ./${tc_worker_type}.json | jq --arg ec2region $region --arg amiid $aws_copied_ami_id -c '(.regions[] | select(.region == $ec2region) | .launchSpec.ImageId) = $amiid' > ./.${tc_worker_type}.json && rm ./${tc_worker_type}.json && mv ./.${tc_worker_type}.json ./${tc_worker_type}.json
  cat ./workertype-secrets.json | jq --arg ec2region $region --arg amiid $aws_copied_ami_id -c '.secret.latest.amis |= . + [{region:$ec2region,"ami-id":$amiid}]' > ./.workertype-secrets.json && rm ./workertype-secrets.json && mv ./.workertype-secrets.json ./workertype-secrets.json

  # purge all but 10 newest workertype amis in region
  aws ec2 describe-images --region ${region} --owners self --filters "Name=name,Values=${tc_worker_type} *" | jq '[ .Images[] | { ImageId, CreationDate, SnapshotId: .BlockDeviceMappings[0].Ebs.SnapshotId } ] | sort_by(.CreationDate) [ 0 : -10 ]' > ./delete-queue-${region}.json
  jq '.|keys[]' ./delete-queue-${region}.json | while read i; do
    old_ami=$(jq -r ".[$i].ImageId" ./delete-queue-${region}.json)
    old_snap=$(jq -r ".[$i].SnapshotId" ./delete-queue-${region}.json)
    old_cd=$(jq ".[$i].CreationDate" ./delete-queue-${region}.json)
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deregistering old ami: ${old_ami}, created: ${old_cd}, in ${region}"
    aws ec2 deregister-image --region ${region} --image-id ${old_ami} || true
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deleting old snapshot: ${old_snap}, for ami: ${old_ami}"
    aws ec2 delete-snapshot --region ${region} --snapshot-id ${old_snap} || true
  done
done

#cat ./${tc_worker_type}.json | curl -D ./update-response-headers.txt --silent --header 'Content-Type: application/json' --request POST --data @- http://taskcluster/aws-provisioner/v1/worker-type/${tc_worker_type}/update > ./update-response.json
#if ! grep -q "HTTP/1.1 200 OK" ./update-response-headers.txt; then
#  echo "ERROR: failed to update provisioner configuration"
#  exit 70
#fi
#echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] worker type updated: https://tools.taskcluster.net/aws-provisioner/#${tc_worker_type}/view"
#echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] active amis (post-update): $(curl --silent http://taskcluster/aws-provisioner/v1/worker-type/${tc_worker_type} | jq -c '[.regions[] | {region: .region, ami: .launchSpec.ImageId}]')"
#cat ./update-response.json | jq '.' > ./${tc_worker_type}-post.json
#git diff --no-index -- ./${tc_worker_type}-pre.json ./${tc_worker_type}-post.json > ./${tc_worker_type}.diff || true

# set latest timestamp and new credentials
cat ./workertype-secrets.json | jq --arg timestamp $(date -u +"%Y-%m-%dT%H:%M:%SZ") --arg rootusername $root_username --arg rootpassword "$root_password" -c '.secret.latest.timestamp = $timestamp | .secret.latest.users.root.username = $rootusername | .secret.latest.users.root.password = $rootpassword' > ./.workertype-secrets.json && rm ./workertype-secrets.json && mv ./.workertype-secrets.json ./workertype-secrets.json
# get previous secrets, move old "latest" to "previous" (list) and discard all but 10 newest records
curl --silent http://taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig:${tc_worker_type} | jq '.secret.previous = (.secret.previous + [.secret.latest] | sort_by(.timestamp) | reverse [0:10]) | del(.secret.latest)' > ./old-workertype-secrets.json
# combine old and new secrets and update tc secret service
jq --arg expires $(date -u +"%Y-%m-%dT%H:%M:%SZ" -d "+1 year") -c -s '{secret:{latest:.[1].secret.latest,previous:.[0].secret.previous},expires: $expires}' ./old-workertype-secrets.json ./workertype-secrets.json | curl --silent --header 'Content-Type: application/json' --request PUT --data @- http://taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig:${tc_worker_type} > ./secret-update-response.json
# clean up
shred -u ./workertype-secrets.json
shred -u ./old-workertype-secrets.json

# wait for copied ami availability in each region
for region in ${ami_copy_regions[@]}; do
  until `aws ec2 wait image-available --region ${region} --image-ids ${copied_regional_ami_ids[$region]} >/dev/null 2>&1`; do
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for ami availability (${region} ${copied_regional_ami_ids[$region]})"
    sleep 30
  done
done

echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] following is a list of all available ${workerType} amis:"
echo "---" > ./ami-latest.yml
echo "---" | tee ./ami-list.yml
for region in ${ami_copy_regions[@]} ${aws_region}; do
  regional_ami_index=0
  echo "${region}:" | tee -a ./ami-list.yml
    aws ec2 describe-images --region ${region} --owners self --filters "Name=name,Values=${workerType} *" | jq -r '[ .Images[] | { ImageId, Name, Description, CreationDate, WorkerType: (.Name | split(" "))[0], OccRevision: (.Name | sub(" version "; " ") | split(" "))[1], BuildTask: (.Name | sub(" version "; " ") | split(" "))[2] } ] | sort_by(.CreationDate) | reverse | .[] | @base64' | while read item; do
      _jq_decode() {
        echo ${item} | base64 --decode | jq -r ${1}
      }
      if [[ "$(_jq_decode '.WorkerType')" == "${tc_worker_type}" ]]; then
        ami_id=$(_jq_decode '.ImageId')
        echo "- id: ${ami_id}" | tee -a ./ami-list.yml
        echo "  name: $(_jq_decode '.Name')" | tee -a ./ami-list.yml
        echo "  description: \"$(_jq_decode '.Description')\"" | tee -a ./ami-list.yml
        echo "  created: $(_jq_decode '.CreationDate')" | tee -a ./ami-list.yml
        echo "  revision: $(_jq_decode '.OccRevision')" | tee -a ./ami-list.yml
        echo "  build: $(_jq_decode '.BuildTask')" | tee -a ./ami-list.yml
        if (( regional_ami_index == 0 )); then
          echo "${region}: ${ami_id}" >> ./ami-latest.yml
        fi
        regional_ami_index=$((regional_ami_index+1))
      fi
  done
done
yq '.' ./ami-list.yml > ./ami-list.json
yq '.' ./ami-latest.yml > ./ami-latest.json

# harvest instance logs
export PAPERTRAIL_API_TOKEN=$(curl -s -N ${secrets_url}:updateworkertype | jq -r '.secret.papertrail.token')
programs=(
  'dsc-run'
  'ec2config.exe'
  'ec2-config'
  'ed25519-public-key'
  'fluentd'
  'haltonidle'
  'maintainsystem'
  'microsoft-windows-dsc'
  'microsoft-windows-security-spp'
  'microsoft-windows-winrm'
  'nxlog'
  'occ-dsc'
  'opencloudconfig'
  'openssh'
  'service_control_manager'
  'stderr'
  'stdout'
  'sysprep-cbs'
  'sysprep-ddaclsys'
  'sysprep-setupact'
  'sysprep-setupapi.app'
  'sysprep-setupapi.dev'
  'user32'
)
for program in ${programs[@]}; do
  if papertrail --system ${aws_instance_id}.${tc_worker_type}.usw2.mozilla.com --min-time "${log_min_time}" "program:${program}" > ./instance-logs/${program}.log && [ -s ./instance-logs/${program}.log ]; then
    rm -f ./instance-logs/no-instance-logs
  elif [ -f ./instance-logs/${program}.log ] && [ ! -s ./instance-logs/${program}.log ] ; then
    rm ./instance-logs/${program}.log
  fi
done
all_program_logs_filename=all-programs-$(date +"%Y%m%d%H%M%S" --utc --date "${log_min_time}")-$(date +"%Y%m%d%H%M%S" --utc)
if papertrail --system ${aws_instance_id}.${tc_worker_type}.usw2.mozilla.com --min-time "${log_min_time}" > ./instance-logs/${all_program_logs_filename}.log && [ -s ./instance-logs/${all_program_logs_filename}.log ]; then
  rm -f ./instance-logs/no-instance-logs
elif [ -f ./instance-logs/${all_program_logs_filename}.log ] && [ ! -s ./instance-logs/${all_program_logs_filename}.log ] ; then
  rm ./instance-logs/${all_program_logs_filename}.log
fi
