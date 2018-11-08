#!/bin/bash
#ansible masters -b -a 'htpasswd -c -b /etc/origin/master/htpasswd admin 1234'
#oc adm policy add-cluster-role-to-user cluster-admin admin

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

ansible localhost -a "sh scripts/create_5G_pvs.sh"
ansible localhost -a "sh scripts/create_10G_pvs.sh"

#ansible localhost -a "cat /root/pvs/* | oc create -f \-" #Command isn't workin: cat: invalid option -- 'f'
cat /root/pvs/* | oc create -f \-

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
oc new-project tasks-test --description="Testing Environment" --display-name="Tasks - Test"
oc new-project tasks-prod --description="Production Environment" --display-name="Tasks - Prod"
oc new-project tasks-build --description="Build Environment" --display-name="Tasks- Build"

# Add policy to allow jenkins to acces tasks-projects
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-dev
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-test
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-prod
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-build

# Import openshif-tasks template
oc project openshift
oc apply -f https://raw.githubusercontent.com/OpenShiftDemos/openshift-tasks/master/app-template.yaml

# Create necessary imange stream
#oc projeect openshift
#oc apply -f https://raw.githubusercontent.com/jboss-openshift/application-templates/master/eap/eap64-image-stream.json

# Deploy app on dev environment
oc project tasks-build
oc new-app openshift-tasks

# Check if jenkins is ready
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' jenkins-cicd-dev.apps.$GUID.example.opentlc.com)" != "302" ]]; do sleep 5; done

# Setup buildconfig for tasks
oc project cicd-dev
oc apply -f ./scripts/tasks-bc.yaml -n cicd-dev
oc start-build tasks-bc -n cicd-dev

# Wait till project is deployed in tasks-dev namespace
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://tasks-tasks-build.apps.be9e.example.opentlc.com/)" != "200" ]]; do sleep 5; done

# Add autoscaling on tasks-dev namespace
oc set resources dc tasks --requests=cpu=100m -n tasks-prod
oc create -f scripts/tasks-hpa.yaml


# Create users for Alpha and Beta clients
ansible masters -m shell -a "sh scripts/add_user.sh"

# Create groups, add user to group, add labels to groups
ansible master -m shell -a "ss scripts/create_groups.sh"

# Setup env for alpha and beta users
oc new-project alphacorp --node-selector='client=alpha'
oc label alphacorp client=alpha
oc adm policy add-role-to-group edit alphacorp -n alphacorp

oc new-project bestacorp --node-selector='client=beta'
oc label betacorp client=beta
oc adm policy add-role-to-group edit betacorp -n betacorp
