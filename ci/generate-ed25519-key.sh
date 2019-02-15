#!/bin/bash

current_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# gw version determined by the gecko-3-b-win2012 manifest in the current repo and branch
generic_worker_version=$(cat ${current_script_dir}/../userdata/Manifest/gecko-3-b-win2012.json | sed -n 's/.*generic-worker\/releases\/download\/v\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')

temp_dir=$(mktemp -d)
curl -sL -o ${temp_dir}/generic-worker-linux-amd64 https://github.com/taskcluster/generic-worker/releases/download/v${generic_worker_version}/generic-worker-linux-amd64
chmod +x ${temp_dir}/generic-worker-linux-amd64

${temp_dir}/generic-worker-linux-amd64 new-ed25519-keypair --file ${temp_dir}/ed25519-private.key > ${temp_dir}/ed25519-public.key

echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ed25519 private key:"
cat ${temp_dir}/ed25519-private.key
echo
echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ed25519 public key:"
cat ${temp_dir}/ed25519-public.key
echo

echo "[opencloudconfig $(date --utc +"%F %T.%3NZ")] ed25519 key created with generic-worker v${generic_worker_version}"

if [ -x "$(command -v pass)" ]; then
  timestamp=$(date -u +%Y%m%d%H%M%S)
  cat ${temp_dir}/ed25519-private.key | pass insert -e Mozilla/relops/cot/ed25519/${timestamp}-gecko-3-b-win2012_private
  cat ${temp_dir}/ed25519-public.key | pass insert -e Mozilla/relops/cot/ed25519/${timestamp}-gecko-3-b-win2012_public
fi


rm -rf ${work_dir}