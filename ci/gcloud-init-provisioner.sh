#!/bin/bash

log_dir=/var/log/releng-gcp-provisioner

# set up papertrail log forwarding
sudo mkdir ${log_dir}
sudo chown ${USER}:${USER} ${log_dir}
#sudo chmod -R o+r ${log_dir}/
sudo curl -sL -o /etc/log_files.yml https://raw.githubusercontent.com/mozilla-releng/OpenCloudConfig/gamma/ci/gcloud-provisioner-log-config.yml >> ${log_dir}/curl-stdout 2>> ${log_dir}/curl-stderr
curl -sLO https://github.com/papertrail/remote_syslog2/releases/download/v0.20/remote-syslog2_0.20_amd64.deb >> ${log_dir}/curl-stdout 2>> ${log_dir}/curl-stderr
sudo dpkg --force-confold -i remote-syslog2_0.20_amd64.deb >> ${log_dir}/dpkg-stdout 2>> ${log_dir}/dpkg-stderr
sudo remote_syslog >> ${log_dir}/remote_syslog-stdout 2>> ${log_dir}/remote_syslog-stderr

# install provisioner and dependencies
sudo apt-get install -y jq >> ${log_dir}/apt-stdout 2>> ${log_dir}/apt-stderr
sudo apt-get install -y git >> ${log_dir}/apt-stdout 2>> ${log_dir}/apt-stderr
git clone https://github.com/mozilla-releng/OpenCloudConfig.git >> ${log_dir}/git-stdout 2>> ${log_dir}/git-stderr
cd OpenCloudConfig
git checkout gamma >> ${log_dir}/git-stdout 2>> ${log_dir}/git-stderr

# run latest provisioner script while logging to ${log_dir}
while true; do
  git pull >> ${log_dir}/git-stdout 2>> ${log_dir}/git-stderr
  ci/gcloud-init.sh >> ${log_dir}/provisioner-stdout 2>> ${log_dir}/provisioner-stderr
  sleep 60
  rm -f ${log_dir}/*
done