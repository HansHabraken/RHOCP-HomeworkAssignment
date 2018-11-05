#!/bin/bash
# RHOCP - Homework Deploy script

#TODO:
# - Domain export
# - Vars file

# Get GUID and export as GUID on all hosts
ansible localhost,all -m shell -a 'export GUID=`hostname | cut -d"." -f2`; echo "export GUID=$GUID" >> $HOME/.bashrc'


# Replace $GUID variable in hosts file with correct GUID
sed -i "s/\$GUID/${GUID}/g" ansible/hosts

# Execute checks
ansible all -m ping
ansible hosts -a "systemctl status docker"
ansible nodes -m yum -a 'list=atomic-openshift-node'


# Execute prerequisites
ansible-playbook -f 20 -i /ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml

# Install openshift openshift cluster
ansible-playbook -f 20 -i /ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml

# After install, copy htpasswd file to master2 and master3
