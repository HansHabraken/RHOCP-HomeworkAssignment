#!/bin/bash

# Get GUID and export as GUID on all hosts
export GUID=`hostname | cut -d"." -f2`

# Replace $GUID variable in hosts file with correct GUID
sed -i "s/\$GUID/${GUID}/g" ansible/hosts

################
#Execute checks#
################

# Validate that all hosts are reachable
ansible all -m ping

# Validate that docker is running
ansible hosts -a "systemctl status docker | grep Active"

ansible nodes -m yum -a 'list=atomic-openshift-node'

###################
#Install Openshift#
###################

# Execute prerequisites
ansible-playbook -f 20 -i ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml

# Install openshift openshift cluster
ansible-playbook -f 20 -i ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml

#####################
#Configure Openshift#
#####################

# Run oc commands on bastion host
ansible masters[0] -b -m fetch -a "src=/root/.kube/config dest=/root/.kube/config flat=yes"

# Login with system:admin
ansible localhost -a "oc login -u system:admin"

# Verify you're sytem:admin
ansible localhost -a "oc whoami"

# Creating persistent volumes
ansible nfs -b -m copy -a "src=scripts/create_pvs.sh dest=/root/create_support_pvs.sh"
ansible nfs -m shell -a "sh /root/create_support_pvs.sh"

ansible localhost -a "sh scrpits/create_5G_vps.sh"
ansible localhost -a "sh scrpits/create_5G_vps.sh"

ansible localhost -a "cat /root/pvs/* | oc create -f -"

ansible nodes -m shell -a "docker pull registry.access.redhat.com/openshift3/ose-recycler:latest"
ansible nodes -m shell -a "docker tag registry.access.redhat.com/openshift3/ose-recycler:latest registry.access.redhat.com/openshift3/ose-recycler:v3.9.30"

# Deploy test application
oc new-project nodejs-test --description="Nodejs Test Project" --display-name="nodejs-test"
oc new-app nodejs-mongo-persistent

#CI/CD - pipeline#
# Create tasks-dev tasks-test tasks-prod projects
oc new-project cicd-dev --description="pizza" --display-name="cicd-dev"

oc new-app jenkins-persistent -p ENABLE_OAUTH=false -e JENKINS_PASSWORD=1234 -n cicd-dev

oc new-project tasks-dev --description="Development Environment" --display-name="Tasks - Dev"
oc new-project tasks-test --description="Testing Environment" --display-name="Test - Dev"
oc new-project tasks-prod --description="Production Environment" --display-name="Prod - Dev"

oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n cicd-dev
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n cicd-test
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n cicd-prod
