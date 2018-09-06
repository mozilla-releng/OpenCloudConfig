import boto3
import datetime
import json
import os
import re
import requests

cache = {}


def get_aws_creds():
    """
    fetch aws credentials from taskcluster secrets.
    """
    url = 'http://{}/secrets/v1/secret/repo:github.com/mozilla-releng/OpenCloudConfig:updateworkertype'.format(os.environ.get('TC_PROXY', 'taskcluster'))
    secret = requests.get(url).json()['secret']
    return secret['aws_tc_account_id'], secret['TASKCLUSTER_AWS_ACCESS_KEY'], secret['TASKCLUSTER_AWS_SECRET_KEY']


def mutate(image, region_name):
    """
    retrieves the properties of interest from the ec2 describe_image json
    """
    name = image['Name'].split()
    return {
        'CreationDate': image['CreationDate'],
        'ImageId': image['ImageId'],
        'WorkerType': name[0],
        'GitSha': name[-1],
        'Region': region_name
    }


def get_ami_list(
    aws_account_id,
    regions=['eu-central-1', 'us-west-1', 'us-west-2', 'us-east-1', 'us-east-2'],
    name_patterns=['gecko-*-b-win* version *', 'gecko-t-win* version *']):
    """
    retrieves a list of amis in the specified regions and matching the specified name patterns
    """
    images = []
    for region_name in regions:
        ec2 = boto3.client('ec2', region_name=region_name)
        response = ec2.describe_images(
            Owners=[aws_account_id],
            Filters=[{'Name': 'name', 'Values': name_patterns}])
        images += [mutate(image, region_name) for image in response['Images']]
    return images


def get_security_groups(
    region,
    groups=['ssh-only', 'rdp-only', 'livelog-direct']):
    """
    retrieves a list of security group ids
    - for the specified security group names
    - in the specified region
    """
    ec2 = boto3.client('ec2', region_name=region)
    response = ec2.describe_security_groups(GroupNames=groups)
    return [x['GroupId'] for x in response['SecurityGroups']]


def get_commit_message(sha, org='mozilla-releng', repo='OpenCloudConfig'):
    """
    retrieves the git commit message associated with the given org, repo and sha 
    """
    return get_commit(sha=sha, org=org, repo=repo)['message']


def get_commit(sha, org='mozilla-releng', repo='OpenCloudConfig'):
    """
    retrieves the git commit push date associated with the given org, repo and sha 
    """
    if sha[:7] in cache:
        return cache[sha[:7]]
    gh_token = os.environ.get('GH_TOKEN')
    if gh_token is not None:
        url = 'https://api.github.com/repos/{}/{}/commits/{}'.format(org, repo, sha)
        response = requests.get(url, headers={'Authorization': 'token {}'.format(gh_token)}).json()
        if 'commit' in response:
            cache[sha[:7]] = response['commit']
            return cache[sha[:7]]
    return {
        'message': None,
        'committer': {
            'date': None,
            'email': None,
            'name': None
        }
    }


def seed_commit_cache(repo_id='52878668', pages=5):
    if cache == {}:
        for page in range(1, pages):
            url = 'https://api.github.com/repositories/{}/commits?page={}'.format(repo_id, pages)
            gh_token = os.environ.get('GH_TOKEN')
            response = requests.get(url) if gh_token is None else requests.get(url, headers={'Authorization': 'token {}'.format(gh_token)})
            if response.status_code == 200:
                for commit in response.json():
                    cache[commit['sha'][:7]] = commit['commit']


def filter_by_sha(ami_list, sha):
    """
    filters the specified ami list by the specified git sha
    """
    for ami in ami_list:
       if ami['GitSha'].startswith(sha) or sha.startswith(ami['GitSha']): yield ami


def log_prefix():
    return '[occ-rollback {}Z]'.format(datetime.datetime.utcnow().isoformat(sep=' ')[:-3])


def post_provisioner_config(worker_type, provisioner_config):
    """
    send provisioner configuration for the specified worker type to taskcluster.
    """
    url = 'http://{}/aws-provisioner/v1/worker-type/{}/update'.format(os.environ.get('TC_PROXY', 'taskcluster'), worker_type)
    return requests.post(url, json=provisioner_config)


seed_commit_cache()
current_sha = os.environ.get('GITHUB_HEAD_SHA')
if current_sha is None:
    print '{} environment variable "GITHUB_HEAD_SHA" not found.'.format(log_prefix())
    quit()


aws_account_id, aws_access_key_id, aws_secret_access_key = get_aws_creds()
boto3.setup_default_session(aws_access_key_id=aws_access_key_id, aws_secret_access_key=aws_secret_access_key)

current_commit_message = get_commit_message(current_sha)
if current_commit_message is None:
    print '{} unable to reach github api (rate throttled)'.format(log_prefix())
    quit()

rollback_syntax_match = re.search('rollback: (gecko-[123]-b-win2012(-beta)?|gecko-t-win(7-32|10-64)(-[^ ])?) ([0-9a-f]{7,40})', current_commit_message, re.IGNORECASE)
if rollback_syntax_match:
    worker_type = rollback_syntax_match.group(1)
    rollback_sha = rollback_syntax_match.group(5)
    ami_list = get_ami_list(aws_account_id, name_patterns=[worker_type + ' version *'])
    sha_list = set([ami['GitSha'] for ami in ami_list])
    available_rollbacks = sorted([{
        'sha': sha[:7],
        'commit': get_commit(sha),
        'amis': filter_by_sha(ami_list, sha)
    } for sha in sha_list], key=lambda x: x['commit']['committer']['date'], reverse=True)
    print '{} available rollbacks:'.format(log_prefix())
    for r in available_rollbacks:
        print '- {} {} {} ({})'.format(r['commit']['committer']['date'], r['sha'], r['commit']['committer']['name'], r['commit']['committer']['email'])
        print '  {}'.format(None if r['commit']['message'] is None else re.sub(r'(\r?\n)+', '\n', r['commit']['message']).strip().replace('\n', '\n  '))
        print '  {}'.format(', '.join(['{} ({})'.format(x['ImageId'], x['Region']) for x in r['amis']]))
    if True in (sha.startswith(rollback_sha) or rollback_sha.startswith(sha) for sha in sha_list):
        print '{} rollback in progress for worker type: {} to amis with git sha: {}'.format(log_prefix(), worker_type, rollback_sha)
        ami_list_for_rollback = filter_by_sha(ami_list, rollback_sha)
        ami_dict = dict((x['Region'], x['ImageId']) for x in ami_list_for_rollback)
        url = 'http://{}/aws-provisioner/v1/worker-type/{}'.format(os.environ.get('TC_PROXY', 'taskcluster'), worker_type)
        provisioner_config = requests.get(url).json()
        provisioner_config.pop('workerType', None)
        provisioner_config.pop('lastModified', None)
        old_regions_config = provisioner_config['regions']
        print '{} old config:'.format(log_prefix())
        print json.dumps(old_regions_config, indent=2, sort_keys=True)
        new_regions_config = [
            {
                'launchSpec': {
                    'ImageId': ami_id,
                    'SecurityGroupIds': get_security_groups(region=region_name)
                },
                'region': region_name,
                'scopes': [],
                'secrets': {},
                'userData': {}
            } for region_name, ami_id in ami_dict.iteritems()]
        print '{} new config:'.format(log_prefix())
        print json.dumps(new_regions_config, indent=2, sort_keys=True)
        provisioner_config['regions'] = new_regions_config
        #creation_date = next((x for x in ami_list_for_rollback if x['Region'] == 'us-west-2'), None)['CreationDate']
        creation_date = get_commit(rollback_sha)['committer']['date']
        manifest_url = 'https://github.com/mozilla-releng/OpenCloudConfig/blob/{}/userdata/Manifest/{}.json'.format(rollback_sha, worker_type)
        provisioner_config['secrets']['generic-worker']['config']['deploymentId'] = current_sha[:12]
        provisioner_config['secrets']['generic-worker']['config']['workerTypeMetadata']['machine-setup'] = {
            'ami-created': creation_date,
            'manifest': manifest_url,
            'note': 'configuration generated with automated rollback at: {}Z'.format(datetime.datetime.utcnow().isoformat(sep=' ')[:-3]),
            'rollback': 'https://github.com/mozilla-releng/OpenCloudConfig/commit/{}'.format(current_sha)
        }
        response = post_provisioner_config(worker_type=worker_type, provisioner_config=provisioner_config)
        if response.status_code == 200:
            print '{} rollback complete.'.format(log_prefix())
        else:
            print '{} rollback failed with status code: {}'.format(log_prefix(), response.status_code)
    else:
        print '{} rollback aborted. no amis found matching worker type: {}, and git sha: {}'.format(log_prefix(), worker_type, rollback_sha)
else:
    print '{} rollback request not detected in commit syntax.'.format(log_prefix())
    ami_list = get_ami_list(aws_account_id)
    print '{} available rollbacks:'.format(log_prefix())
    for worker_type in sorted(set([ami['WorkerType'] for ami in ami_list])):
        print '- {}'.format(worker_type)
        worker_type_ami_list = filter(lambda x: x['WorkerType'] == worker_type, ami_list)
        sha_list = set([ami['GitSha'] for ami in worker_type_ami_list])
        available_rollbacks = sorted([{
            'sha': sha[:7],
            'commit': get_commit(sha),
            'amis': filter_by_sha(worker_type_ami_list, sha)
        } for sha in sha_list], key=lambda x: x['commit']['committer']['date'], reverse=True)
        for r in available_rollbacks:
            print '  - {} {} {} ({})'.format(r['commit']['committer']['date'], r['sha'], r['commit']['committer']['name'], r['commit']['committer']['email'])
            print '    {}'.format(None if r['commit']['message'] is None else re.sub(r'(\r?\n)+', '\n', r['commit']['message']).strip().replace('\n', '\n    '))
            print '    {}'.format(', '.join(['{} ({})'.format(x['ImageId'], x['Region']) for x in r['amis']]))