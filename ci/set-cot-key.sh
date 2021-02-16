#!/bin/bash

for pool in gecko-3-b-win2012 gecko-3-b-win2012-c4 gecko-3-b-win2012-c5; do
  instance=$(aws ec2 describe-instances --profile moz-tc --region us-west-2 --filters Name=key-name,Values=mozilla-taskcluster-worker-${pool} Name=instance-state-name,Values=running --query Reservations[0].Instances[0] | jq -c -r '.InstanceId, .NetworkInterfaces[0].Association.PublicIp')
  read -r instance_id public_ip <<<"${instance//$'\n'/ }"
  userdata=$(aws ec2 describe-instance-attribute --profile moz-tc --region us-west-2 --instance-id ${instance_id} --attribute userData | jq -r '.UserData.Value' | base64 --decode)
  unset password
  [[ ${userdata} =~ \<rootPassword\>([^<]+)\</rootPassword\> ]] && password=${BASH_REMATCH[1]}
  echo "instance id: ${instance_id}, public ip: ${public_ip}, password: ${password}"
  xfreerdp /u:Administrator /p:"${password}" /kbd:809 /w:2400 /h:1200 +clipboard /v:${public_ip}
done
