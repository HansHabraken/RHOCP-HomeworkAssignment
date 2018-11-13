#!/usr/bin/env bash
set -o errexit
set -o nounset

# Download git repository
git clone https://github.com/HansHabraken/RHOCP-HomeworkAssignment.git

# Go to directory
cd RHOCP-HomeworkAssignment

# Get GUID and export as GUID on all hosts
echo "export GUID"
export GUID=`hostname | cut -d"." -f2`

# Replace $GUID variable in hosts file with correct GUID
echo 'Replace GUID'
sed -i "s/\$GUID/${GUID}/g" ./hosts

################
#Execute checks#
################
echo 'Execute checks'

# Validate that all hosts are reachable
echo 'Check: ping'
ansible all -m ping

# Validate that docker is running
echo 'Check: docker'
ansible nodes -a "systemctl status docker | grep Active"
echo 'Check: packages'
ansible nodes -m yum -a 'list=atomic-openshift-node'

###################
#Install Openshift#
###################
echo "Install openshift"

# Execute prerequisites
echo 'Execute prerequisistes'
ansible-playbook -f 20 -i ./hosts /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml

# Install openshift openshift cluster
echo 'Install openshift'
ansible-playbook -f 20 -i ./hosts /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml

#####################
#Configure Openshift#
#####################
echo 'Configure openshift'

# Run oc commands on bastion host
ansible masters[0] -b -m fetch -a "src=/root/.kube/config dest=/root/.kube/config flat=yes"

# Login with system:admin
ansible localhost -a "oc login -u system:admin"

# Verify you're sytem:admin
ansible localhost -a "oc whoami"

# Creating persistent volumes
echo 'Creating persisten volumes'
ansible nfs -b -m copy -a "src=scripts/create_pvs.sh dest=/root/create_support_pvs.sh"
ansible nfs -m shell -a "sh /root/create_support_pvs.sh"

ansible localhost -a "sh scripts/create_5G_pvs.sh"
ansible localhost -a "sh scripts/create_10G_pvs.sh"

#ansible localhost -a "cat /root/pvs/* | oc create -f \-" #Command isn't workin: cat: invalid option -- 'f'
cat /root/pvs/* | oc create -f \-

ansible nodes -m shell -a "docker pull registry.access.redhat.com/openshift3/ose-recycler:latest"
ansible nodes -m shell -a "docker tag registry.access.redhat.com/openshift3/ose-recycler:latest registry.access.redhat.com/openshift3/ose-recycler:v3.9.30"

# Create admin user
echo "Creating admin user"
ansible masters -b -a 'htpasswd -c -b /etc/origin/master/htpasswd admin 1234'
oc adm policy add-cluster-role-to-user cluster-admin admin

# Apply new project template
echo "Apply new project template"
oc apply -f yaml-files/project_template.yaml

# Restart services
echo "Restart services"
ansible masters -a "systemctl restart atomic-openshift-master-api"
ansible masters -a "systemctl restart atomic-openshift-master-controllers"


# Deploy test application
echo 'Deploy test application'
oc new-project nodejs-test --description="Nodejs Test Project" --display-name="nodejs-test"
oc new-app nodejs-mongo-persistent


##################
#CI/CD - pipeline#
##################
echo 'Intall CI/CD - pipeline'

# Create tasks-dev tasks-test tasks-prod projects
echo "Creating projects"
oc new-project cicd-dev --description="pizza" --display-name="cicd-dev"
oc new-app jenkins-persistent -p ENABLE_OAUTH=false -e JENKINS_PASSWORD=1234 -n cicd-dev

oc new-project tasks-dev --description="Development Environment" --display-name="Tasks - Dev"
oc new-project tasks-test --description="Testing Environment" --display-name="Tasks - Test"
oc new-project tasks-prod --description="Production Environment" --display-name="Tasks - Prod"
oc new-project tasks-build --description="Build Environment" --display-name="Tasks- Build"

# Add policy to allow jenkins to acces tasks-projects
echo 'Add policy'
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-dev
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-test
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-prod
oc adm policy add-role-to-user edit system:serviceaccount:cicd-dev:jenkins -n tasks-build

# Import openshift-tasks template
echo 'Import openshift-tasks template '
oc project openshift
oc apply -f https://raw.githubusercontent.com/OpenShiftDemos/openshift-tasks/master/app-template.yaml

# Create necessary imange stream
oc project openshift
oc apply -f https://raw.githubusercontent.com/jboss-openshift/application-templates/master/eap/eap64-image-stream.json

# Deploy app on build environment
echo "Deploy openshift-tasks on build env"
oc project tasks-build
oc new-app openshift-tasks

# Export GUID
echo "export GUID"
export GUID=`hostname | cut -d"." -f2`

# Check if jenkins is ready (not working yet)
#echo "Check: jenkins ready"
#while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' jenkins-cicd-dev.apps.$GUID.example.opentlc.com)" != "302" ]]; do sleep 5; done

# Setup buildconfig for tasks
echo "Setup buildconfig"
oc project cicd-dev
oc apply -f ./yaml-files/tasks-bc.yaml -n cicd-dev
oc start-build tasks-bc -n cicd-dev

# Wait till project is deployed in tasks-prod namespace
echo "Check: app is deployed"
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://tasks-tasks-prod.apps.$GUID.example.opentlc.com)" != "200" ]]; do sleep 5; done

# Add autoscaling on tasks-dev namespace
echo "Add autoscaling"
oc project tasks-prod
oc set resources dc tasks --requests=cpu=100m -n tasks-prod
oc create -f yaml-files/tasks-hpa.yaml -n tasks-prod

############
#Multitancy#
############

# Create users for Alpha and Beta clients
echo "Create users"
ansible localhost -m shell -a "sh scripts/add_users.sh"

# Create groups, add user to group, add labels to groups
echo "Create groups"
ansible localhost -a "sh scripts/create_groups.sh"

# Label nodes
echo "Label nodes"
oc label node node1.$GUID.internal client=alpha
oc label node node2.$GUID.internal client=beta
oc label node node3.$GUID.internal client=common

# Setup env for alpha and beta users
echo "Setup env for alpha and beta users"
oc adm new-project alphacorp-project --node-selector="client=alpha"
oc adm policy add-role-to-group edit alphacorp -n alphacorp-project

oc adm new-project betacorp-project --node-selector='client=beta'
oc adm policy add-role-to-group edit betacorp -n betacorp-project

# Modify master-config
echo "Modify master-config"
ansible masters -m shell -a "sed -i 's/projectRequestTemplate.*/projectRequestTemplate\: \"default\/project-request\"/g' /etc/origin/master/master-config.yaml"
ansible masters -m shell -a'systemctl restart atomic-openshift-master-api'
ansible masters -m shell -a'systemctl restart atomic-openshift-master-controllers'
