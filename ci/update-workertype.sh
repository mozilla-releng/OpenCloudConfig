#!/bin/bash -e

shopt -s extglob

if [ "${#}" -lt 1 ]; then
  echo "workertype argument missing; usage: ./update-workertype.sh workertype" >&2
  exit 64
fi
tc_worker_type="${1}"

# validate that manifest components, which contain a sha512 hash, have a corresponding tooltool artifact
secrets_url="taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig:updatetooltoolrepo"
curl -s -N ${secrets_url} | jq -r '.secret.tooltool.upload.internal' > ./.tooltool.token
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] tooltool token downloaded"
manifest=./OpenCloudConfig/userdata/Manifest/${tc_worker_type}.json
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] validating Manifest ${manifest}"
json=$(basename $manifest)
for ComponentType in ExeInstall MsiInstall MsuInstall ZipInstall; do
  jq --arg componentType ${ComponentType} -r '.Components[] | select(.ComponentType == $componentType and (.sha512 != "" and .sha512 != null)) | .sha512' ${manifest} | while read sha512; do
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] validating ${ComponentType} ${sha512}"

    tt_url="https://tooltool.mozilla-releng.net/sha512/${sha512}"
    if curl --header "Authorization: Bearer $(cat ./.tooltool.token)" --output /dev/null --silent --head --fail ${tt_url}; then
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ${sha512} found in tooltool: ${tt_url}"
    else
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ${sha512} missing from tooltool: ${tt_url}"
      exit 63
    fi
  done
done

# get some secrets from tc
secrets_url=taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig
if [[ $tc_worker_type == *"-b-win"* ]]; then
  cot_private_key="$(curl -s -N ${secrets_url}:cot-${tc_worker_type} | jq -r '.secret.cot_private_key')"
  if [ -z "${cot_private_key}" ]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] cot private key retrieval failed."
  else
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] cot private key retrieval suceeeded."
  fi
else
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] cot private key retrieval skipped."
fi
read TASKCLUSTER_AWS_ACCESS_KEY TASKCLUSTER_AWS_SECRET_KEY aws_tc_account_id userdata<<EOF
$(curl -s -N ${secrets_url}:updateworkertype | jq ". | .secret.cotGpgKey=\"${cot_private_key}\"" | python -c 'import json, sys; a = json.load(sys.stdin)["secret"]; print a["TASKCLUSTER_AWS_ACCESS_KEY"], a["TASKCLUSTER_AWS_SECRET_KEY"], a["aws_tc_account_id"], ("<powershell>\nInvoke-Expression (New-Object Net.WebClient).DownloadString(('\''https://raw.githubusercontent.com/MozRelOps/OpenCloudConfig/master/userdata/rundsc.ps1?{0}'\'' -f [Guid]::NewGuid()))\n</powershell>\n<persist>true</persist>\n<secrets>\n  <rootPassword>ROOTPASSWORDTOKEN</rootPassword>\n  <rootGpgKey>\n%s\n</rootGpgKey>\n  <workerPassword>WORKERPASSWORDTOKEN</workerPassword>\n  <cotGpgKey>\n%s\n</cotGpgKey>\n</secrets>" % (a["rootGpgKey"], a["cotGpgKey"])).replace("\n", "\\\\n");' 2> /dev/null)
EOF

: ${TASKCLUSTER_AWS_ACCESS_KEY:?"TASKCLUSTER_AWS_ACCESS_KEY is not set"}
: ${TASKCLUSTER_AWS_SECRET_KEY:?"TASKCLUSTER_AWS_SECRET_KEY is not set"}
export AWS_ACCESS_KEY_ID=${TASKCLUSTER_AWS_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${TASKCLUSTER_AWS_SECRET_KEY}

: ${aws_tc_account_id:?"aws_tc_account_id is not set"}

aws_region=${aws_region:='us-west-2'}

aws_key_name="mozilla-taskcluster-worker-${tc_worker_type}"
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] aws_key_name: ${aws_key_name}"

aws_client_token=${GITHUB_HEAD_SHA:0:12}
echo "{\"secret\":{\"latest\":{\"timestamp\":\"\",\"git-sha\":\"${GITHUB_HEAD_SHA:0:12}\"}}}" | jq '.' > ./workertype-secrets.json

commit_message=$(curl --silent https://api.github.com/repos/mozilla-releng/OpenCloudConfig/git/commits/${GITHUB_HEAD_SHA} | jq -r '.message')
if [[ $commit_message == *"nodeploy:"* ]]; then
  no_deploy_list=$([[ ${commit_message} =~ nodeploy:\s+?([^;]*) ]] && echo "${BASH_REMATCH[1]}")
  if [[ " ${no_deploy_list[*]} " == *" ${tc_worker_type} "* ]]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment skipped due to presence of ${tc_worker_type} in commit message no-deploy list (${no_deploy_list[*]})"
    exit
  fi
elif [[ $commit_message == *"deploy: all"* ]]; then
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deploying ${tc_worker_type} as part of 'deploy: all'"
elif [[ $commit_message == *"deploy:"* ]]; then
  deploy_list=$([[ ${commit_message} =~ deploy:\s+?([^;]*) ]] && echo "${BASH_REMATCH[1]}")
  if [[ " ${deploy_list[*]} " != *" ${tc_worker_type} "* ]]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment skipped due to absence of ${tc_worker_type} in commit message deploy list (${deploy_list[*]})"
    exit
  fi
else
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] deployment skipped due to absent deploy instruction in commit message (${commit_message})"
  exit
fi

echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] git sha: ${aws_client_token} used for aws client token"

case "${tc_worker_type}" in
  gecko-t-win7-32-gpu*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='gecko-t-win7-32-base-20171018'}
    aws_instance_type=${aws_instance_type:='g2.2xlarge'}
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko test worker for Windows 7 32 bit; TaskCluster worker type: ${tc_worker_type}, OCC version ${aws_client_token}, https://github.com/mozilla-releng/OpenCloudConfig/tree/${GITHUB_HEAD_SHA}"}
    gw_tasks_dir='Z:\'
    root_username=root
    worker_username=GenericWorker
    block_device_mappings='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeType":"gp2","VolumeSize":30,"DeleteOnTermination":true}},{"DeviceName":"/dev/sdb","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}},{"DeviceName":"/dev/sdc","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}}]'
    ;;
  gecko-t-win7-32*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='gecko-t-win7-32-base-20171018'}
    aws_instance_type=${aws_instance_type:='c4.2xlarge'}
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko test worker for Windows 7 32 bit; TaskCluster worker type: ${tc_worker_type}, OCC version ${aws_client_token}, https://github.com/mozilla-releng/OpenCloudConfig/tree/${GITHUB_HEAD_SHA}"}
    gw_tasks_dir='Z:\'
    root_username=root
    worker_username=GenericWorker
    block_device_mappings='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeType":"gp2","VolumeSize":30,"DeleteOnTermination":true}},{"DeviceName":"/dev/sdb","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}},{"DeviceName":"/dev/sdc","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}}]'
    ;;
  gecko-t-win10-64-gpu*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='gecko-t-win10-64-gpu-base-20180320'}
    aws_instance_type=${aws_instance_type:='g2.2xlarge'}
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko tester for Windows 10 64 bit; TaskCluster worker type: ${tc_worker_type}, OCC version ${aws_client_token}, https://github.com/mozilla-releng/OpenCloudConfig/tree/${GITHUB_HEAD_SHA}"}
    gw_tasks_dir='Z:\'
    root_username=Administrator
    worker_username=GenericWorker
    block_device_mappings='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}},{"DeviceName":"/dev/sdb","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}}]'
    ;;
  gecko-t-win10-64*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='gecko-t-win10-64-base-20180320'}
    aws_instance_type=${aws_instance_type:='c4.2xlarge'}
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko tester for Windows 10 64 bit; TaskCluster worker type: ${tc_worker_type}, OCC version ${aws_client_token}, https://github.com/mozilla-releng/OpenCloudConfig/tree/${GITHUB_HEAD_SHA}"}
    gw_tasks_dir='Z:\'
    root_username=Administrator
    worker_username=GenericWorker
    block_device_mappings='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}},{"DeviceName":"/dev/sdb","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}}]'
    ;;
  gecko-[123]-b-win2012*)
    aws_base_ami_search_term=${aws_base_ami_search_term:='gecko-b-win2012-ena-base-*'}
    aws_instance_type=${aws_instance_type:='c5.4xlarge'}
    aws_base_ami_id="$(aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=state,Values=available" "Name=name,Values=${aws_base_ami_search_term}" --query 'Images[*].{A:CreationDate,B:ImageId}' --output text | sort -u | tail -1 | cut -f2)"
    ami_description="Gecko builder for Windows; TaskCluster worker type: ${tc_worker_type}, OCC version ${aws_client_token}, https://github.com/mozilla-releng/OpenCloudConfig/tree/${GITHUB_HEAD_SHA}"}
    gw_tasks_dir='Z:\'
    root_username=Administrator
    worker_username=GenericWorker
    block_device_mappings='[{"DeviceName":"/dev/sda1","Ebs":{"VolumeType":"gp2","VolumeSize":40,"DeleteOnTermination":true}},{"DeviceName":"/dev/sdb","Ebs":{"VolumeType":"gp2","VolumeSize":120,"DeleteOnTermination":true}}]'
    ;;
  *)
    echo "ERROR: unknown worker type: '${tc_worker_type}'"
    exit 67
    ;;
esac
if [ -z "${aws_base_ami_id}" ]; then
  echo "ERROR: failed to find a suitable base ami matching: '${aws_base_ami_search_term}'"
  exit 69
fi

occ_manifest="https://github.com/mozilla-releng/OpenCloudConfig/blob/${GITHUB_HEAD_SHA}/userdata/Manifest/${tc_worker_type}.json"

root_password="$(pwgen -1sBync 16)"
root_password="${root_password//[<>\"\'\`\\\/]/_}"
worker_password="$(pwgen -1sBync 16)"
worker_password="${worker_password//[<>\"\'\`\\\/]/_}"
userdata=${userdata/ROOTPASSWORDTOKEN/$root_password}
userdata=${userdata/WORKERPASSWORDTOKEN/$worker_password}

curl --silent http://taskcluster/aws-provisioner/v1/worker-type/${tc_worker_type} | jq '.' > ./${tc_worker_type}-pre.json
cat ./${tc_worker_type}-pre.json | jq --arg gwtasksdir $gw_tasks_dir --arg occmanifest $occ_manifest --arg deploydate "$(date --utc +"%F %T.%3NZ")" --arg awsinstancetype $aws_instance_type --arg deploymentId $aws_client_token --argjson blockDeviceMappings $block_device_mappings -c 'del(.workerType, .lastModified) | .secrets."generic-worker".config.tasksDir = $gwtasksdir | .secrets."generic-worker".config.workerTypeMetadata."machine-setup".manifest = $occmanifest | .secrets."generic-worker".config.workerTypeMetadata."machine-setup"."ami-created" = $deploydate | .instanceTypes[].instanceType = $awsinstancetype | .instanceTypes[].launchSpec.BlockDeviceMappings = $blockDeviceMappings | .secrets."generic-worker".config.deploymentId = $deploymentId' > ./${tc_worker_type}.json
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] active amis (pre-update): $(cat ./${tc_worker_type}.json | jq -c '[.regions[] | {region: .region, ami: .launchSpec.ImageId}]')"

echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] latest base ami for: ${aws_base_ami_search_term}, in region: ${aws_region}, is: ${aws_base_ami_id}"

# create instance, apply user-data, filter output, get instance id, tag instance, wait for shutdown
while [ -z "$aws_instance_id" ]; do
  aws_instance_id="$(aws ec2 run-instances --region ${aws_region} --image-id "${aws_base_ami_id}" --key-name ${aws_key_name} --security-group-ids "sg-3bd7bf41" --subnet-id "subnet-f94cb29f" --user-data "$(echo -e ${userdata})" --instance-type ${aws_instance_type} --block-device-mappings "${block_device_mappings}" --instance-initiated-shutdown-behavior stop --client-token "${tc_worker_type}-${aws_client_token}" | sed -n 's/^ *"InstanceId": "\(.*\)", */\1/p')"
  if [ -z "$aws_instance_id" ]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] create instance failed. retrying..."
  fi
done
until `aws ec2 create-tags --region ${aws_region} --resources "${aws_instance_id}" --tags "Key=WorkerType,Value=golden-${tc_worker_type}" >/dev/null 2>&1`;
do
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for instance instantiation"
done
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] instance: ${aws_instance_id} instantiated and tagged: WorkerType=golden-${tc_worker_type} (https://${aws_region}.console.aws.amazon.com/ec2/v2/home?region=${aws_region}#Instances:instanceId=${aws_instance_id})"
sleep 30 # give aws 30 seconds to start the instance
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] userdata logging to: https://papertrailapp.com/groups/2488493/events?q=${aws_instance_id}"
aws_instance_public_ip="$(aws ec2 describe-instances --region ${aws_region} --instance-id "${aws_instance_id}" --query 'Reservations[*].Instances[*].NetworkInterfaces[*].Association.PublicIp' --output text)"
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] instance public ip: ${aws_instance_public_ip}"

# wait for instance stopped state
until `aws ec2 wait instance-stopped --region ${aws_region} --instance-ids "${aws_instance_id}" >/dev/null 2>&1`;
do
  instance_state=$(aws ec2 describe-instances --region ${aws_region} --instance-id ${aws_instance_id} --query 'Reservations[*].Instances[*].State.Name' --output text)
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for instance to shut down. current state: ${instance_state}"
  if [ "${instance_state}" == "terminated" ]; then
    exit 68
  fi
done

# create ami, get ami id, tag ami, wait for ami availability
while [ -z "$aws_ami_id" ]; do
  # if we are dynamically adding the y: and z: ebs volume, detach and discard it before capturing ami.
  if [[ $block_device_mappings == *"/dev/sdb"* ]]; then
    dev_sdb_volume_id=$(aws ec2 describe-instances --region ${aws_region} --instance-id ${aws_instance_id} --query 'Reservations[*].Instances[*].BlockDeviceMappings[1].Ebs.VolumeId' --output text)
    if [[ $block_device_mappings == *"/dev/sdc"* ]]; then
      dev_sdc_volume_id=$(aws ec2 describe-instances --region ${aws_region} --instance-id ${aws_instance_id} --query 'Reservations[*].Instances[*].BlockDeviceMappings[2].Ebs.VolumeId' --output text)
      aws ec2 detach-volume --region ${aws_region} --instance-id ${aws_instance_id} --device /dev/sdc --volume-id ${dev_sdc_volume_id}
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdc_volume_id} detached from ${aws_instance_id} /dev/sdc"
      aws ec2 delete-volume --region ${aws_region} --volume-id ${dev_sdc_volume_id}
      echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdc_volume_id} deleted"
    fi
    aws ec2 detach-volume --region ${aws_region} --instance-id ${aws_instance_id} --device /dev/sdb --volume-id ${dev_sdb_volume_id}
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdb_volume_id} detached from ${aws_instance_id} /dev/sdb"
    aws ec2 delete-volume --region ${aws_region} --volume-id ${dev_sdb_volume_id}
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] volume: ${dev_sdb_volume_id} deleted"
  fi
  aws_ami_id=`aws ec2 create-image --region ${aws_region} --instance-id ${aws_instance_id} --name "${tc_worker_type} version ${aws_client_token}" --description "${ami_description}" | sed -n 's/^ *"ImageId": *"\(.*\)" *$/\1/p'`
  if [ -z "$aws_ami_id" ]; then
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] create image failed. retrying..."
  fi
done
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ami: ${aws_ami_id} creation in progress: https://${aws_region}.console.aws.amazon.com/ec2/v2/home?region=${aws_region}#Images:visibility=owned-by-me;search=${aws_ami_id}"
aws ec2 create-tags --region ${aws_region} --resources "${aws_ami_id}" --tags "Key=WorkerType,Value=${tc_worker_type}"
sleep 30
until `aws ec2 wait image-available --region ${aws_region} --image-ids "${aws_ami_id}" >/dev/null 2>&1`;
do
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for ami availability (${aws_region} ${aws_ami_id})"
done
cat ./${tc_worker_type}.json | jq --arg ec2region $aws_region --arg amiid $aws_ami_id -c '(.regions[] | select(.region == $ec2region) | .launchSpec.ImageId) = $amiid' > ./.${tc_worker_type}.json && rm ./${tc_worker_type}.json && mv ./.${tc_worker_type}.json ./${tc_worker_type}.json
cat ./workertype-secrets.json | jq --arg ec2region $aws_region --arg amiid $aws_ami_id -c '.secret.latest.amis |= . + [{region:$ec2region,"ami-id":$amiid}]' > ./.workertype-secrets.json && rm ./workertype-secrets.json && mv ./.workertype-secrets.json ./workertype-secrets.json

# purge all but 10 newest workertype amis in region
aws ec2 describe-images --region ${aws_region} --owners self --filters "Name=name,Values=${tc_worker_type} version*" | jq '[ .Images[] | { ImageId, CreationDate, SnapshotId: .BlockDeviceMappings[0].Ebs.SnapshotId } ] | sort_by(.CreationDate) [ 0 : -10 ]' > ./delete-queue-${aws_region}.json
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

# copy ami to each configured region, get copied ami id, tag copied ami, wait for copied ami availability
jq -c '[.regions[].region] | .[]' ./${tc_worker_type}.json | sed 's/"//g' | grep -Fvx "${aws_region}" | while read region; do
  aws_copied_ami_id=`aws ec2 copy-image --region ${region} --source-region ${aws_region} --source-image-id ${aws_ami_id} --name "${tc_worker_type} version ${aws_client_token}" --description "${ami_description}" | sed -n 's/^ *"ImageId": *"\(.*\)" *$/\1/p'`
  echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ami: ${aws_region} ${aws_ami_id} copy to ${region} ${aws_copied_ami_id} in progress: https://${region}.console.aws.amazon.com/ec2/v2/home?region=${region}#Images:visibility=owned-by-me;search=${aws_copied_ami_id}"
  aws ec2 create-tags --region ${region} --resources "${aws_copied_ami_id}" --tags "Key=WorkerType,Value=${tc_worker_type}"
  sleep 30
  until `aws ec2 wait image-available --region ${region} --image-ids "${aws_copied_ami_id}" >/dev/null 2>&1`;
  do
    echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] waiting for ami availability (${region} ${aws_copied_ami_id})"
  done
  cat ./${tc_worker_type}.json | jq --arg ec2region $region --arg amiid $aws_copied_ami_id -c '(.regions[] | select(.region == $ec2region) | .launchSpec.ImageId) = $amiid' > ./.${tc_worker_type}.json && rm ./${tc_worker_type}.json && mv ./.${tc_worker_type}.json ./${tc_worker_type}.json
  cat ./workertype-secrets.json | jq --arg ec2region $region --arg amiid $aws_copied_ami_id -c '.secret.latest.amis |= . + [{region:$ec2region,"ami-id":$amiid}]' > ./.workertype-secrets.json && rm ./workertype-secrets.json && mv ./.workertype-secrets.json ./workertype-secrets.json

  # purge all but 10 newest workertype amis in region
  aws ec2 describe-images --region ${region} --owners self --filters "Name=name,Values=${tc_worker_type} version*" | jq '[ .Images[] | { ImageId, CreationDate, SnapshotId: .BlockDeviceMappings[0].Ebs.SnapshotId } ] | sort_by(.CreationDate) [ 0 : -10 ]' > ./delete-queue-${region}.json
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

# Overlay userdata/Configuration/GenericWorker/generic-worker.config on top of the generic-worker config section of the worker type definition.
# Only required for generic worker version 10 and higher.
# Once all workers are on generic-worker version 10 or higher, we can remove this hacky if statement (but keep the lines inside the if statement).
if [ "$(cat OpenCloudConfig/userdata/Manifest/${tc_worker_type}.json | sed -n 's/.*generic-worker\/releases\/download\/v\([0-9]*\)\..*/\1/p')" -ge 10 ]; then
  # Decide key runTasksAsCurrentUser based on whether worker type name ends in '-cu'
  runTasksAsCurrentUser='false'
  [ "${tc_worker_type:0,-3}" == '-cu' ] && runTasksAsCurrentUser='true'
  echo $(cat ${tc_worker_type}.json | jq '.secrets."generic-worker".config') $(cat OpenCloudConfig/userdata/Configuration/GenericWorker/generic-worker.config | jq ".runTasksAsCurrentUser = ${runTasksAsCurrentUser}") | jq --slurp add > merged-gw-config.json
  cat ${tc_worker_type}.json | jq --sort-keys --slurpfile 'gwconfig' merged-gw-config.json '.secrets."generic-worker".config=$gwconfig[0]' > .${tc_worker_type}.json && rm ${tc_worker_type}.json && mv .${tc_worker_type}.json ${tc_worker_type}.json
fi

cat ./${tc_worker_type}.json | curl --silent --header 'Content-Type: application/json' --request POST --data @- http://taskcluster/aws-provisioner/v1/worker-type/${tc_worker_type}/update > ./update-response.json
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] worker type updated: https://tools.taskcluster.net/aws-provisioner/#${tc_worker_type}/view"
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] active amis (post-update): $(curl --silent http://taskcluster/aws-provisioner/v1/worker-type/${tc_worker_type} | jq -c '[.regions[] | {region: .region, ami: .launchSpec.ImageId}]')"

cat ./update-response.json | jq '.' > ./${tc_worker_type}-post.json
git diff --no-index -- ./${tc_worker_type}-pre.json ./${tc_worker_type}-post.json > ./${tc_worker_type}.diff || true

# set latest timestamp and new credentials
cat ./workertype-secrets.json | jq --arg timestamp $(date -u +"%Y-%m-%dT%H:%M:%SZ") --arg rootusername $root_username --arg rootpassword "$root_password" --arg workerusername $worker_username --arg workerpassword "$worker_password" -c '.secret.latest.timestamp = $timestamp | .secret.latest.users.root.username = $rootusername | .secret.latest.users.root.password = $rootpassword | .secret.latest.users.worker.username = "GenericWorker" | .secret.latest.users.worker.password = $workerpassword' > ./.workertype-secrets.json && rm ./workertype-secrets.json && mv ./.workertype-secrets.json ./workertype-secrets.json
# get previous secrets, move old "latest" to "previous" (list) and discard all but 10 newest records
curl --silent http://taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig:${tc_worker_type} | jq '.secret.previous = (.secret.previous + [.secret.latest] | sort_by(.timestamp) | reverse [0:10]) | del(.secret.latest)' > ./old-workertype-secrets.json
# combine old and new secrets and update tc secret service
jq --arg expires $(date -u +"%Y-%m-%dT%H:%M:%SZ" -d "+1 year") -c -s '{secret:{latest:.[1].secret.latest,previous:.[0].secret.previous},expires: $expires}' ./old-workertype-secrets.json ./workertype-secrets.json | curl --silent --header 'Content-Type: application/json' --request PUT --data @- http://taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig:${tc_worker_type} > ./secret-update-response.json
# clean up
shred -u ./workertype-secrets.json
shred -u ./old-workertype-secrets.json
