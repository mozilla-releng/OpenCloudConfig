the authorized_keys file in this directory is added to each instance instantiated by occ at C:\Users\Administrator\.ssh\authorized_keys with the exception of worker type gecko-3-b-win2012 where no ssh server is installed.

users whose keys are contained in this file may connect to taskcluster workers via ssh. users will also require access to the ec2 console in order to apply security group settings that will allow ssh access to the instance in question.

members of github org: mozilla-releng (https://github.com/orgs/mozilla-releng/people), may create pull requests, adding or removing their own public key(s) only.

keys should comply with guidelines at https://infosec.mozilla.org/guidelines/openssh#key-generation.

keys with a bit length less than 4096 will be rejected. you can check the bit length of your ssh public key with a command similar to this:

```
ssh-keygen -lf ~/.ssh/id_rsa.pub
```

ssh access to taskcluster worker types is audited.
