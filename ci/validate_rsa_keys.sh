#!/bin/bash -e

while read pub_key; do
  rsa_bit_length=$(echo ${pub_key} | ssh-keygen -lf - | { read -a i; echo ${i[0]}; })
  if [ ${rsa_bit_length} -lt 2048 ]; then
    (>&2 echo "key (${pub_key##* }) with rsa bit length of ${rsa_bit_length} is rejected.")
    exit 1
  fi
done < ./OpenCloudConfig/userdata/Configuration/ssh/authorized_keys
exit