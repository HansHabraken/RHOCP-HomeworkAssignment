#!/bin/bash
# RHOCP - Homework Deploy script

#TODO:
# - Domain export
# - Vars file

# Get GUID and export as GUID on all hosts
export GUID=`hostname | cut -d"." -f2`


# Replace $GUID variable in hosts file with correct GUID
sed -i "s/\$GUID/${GUID}/g" ansible/hosts

# Execute checks
#ansible all -m ping
#ansible hosts -a "systemctl status docker"
#ansible nodes -m yum -a 'list=atomic-openshift-node'


# Execute prerequisites
ansible-playbook -f 20 -i ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml

# Install openshift openshift cluster
ansible-playbook -f 20 -i ansible/hosts /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml

# Configure Openshift Cluster
# Run oc commands on bastion host
ansible masters[0] -b -m fetch -a "src=/root/.kube/config dest=/root/.kube/config flat=yes"


# Creating persistent volumes

cat << EOF > /root/presistentVolumes.sh
sudo -i
mkdir -p /srv/nfs/user-vols/pv{1..200}

for pvnum in {1..50} ; do
echo /srv/nfs/user-vols/pv${pvnum} *(rw,root_squash) >> /etc/exports.d/openshift-uservols.exports
chown -R nfsnobody.nfsnobody  /srv/nfs
chmod -R 777 /srv/nfs
done

systemctl restart nfs-server
exit
exit

EOF

scp /root/presistentVolumes.sh support1.$GUID.internal:/home/ec2-user/presistentVolumes.sh
ssh support1.$GUID.internal ./presistentVolumes

# pv1 to pv25 with a size of 5 GB and ReadWriteOnce access mode
export volsize="5Gi"
mkdir /root/pvs
for volume in pv{1..25} ; do
cat << EOF > /root/pvs/${volume}
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "${volume}"
  },
  "spec": {
    "capacity": {
        "storage": "${volsize}"
    },
    "accessModes": [ "ReadWriteOnce" ],
    "nfs": {
        "path": "/srv/nfs/user-vols/${volume}",
        "server": "support1.${GUID}.internal"
    },
    "persistentVolumeReclaimPolicy": "Recycle"
  }
}
EOF
echo "Created def file for ${volume}";
done;

# pv26 to pv50 with a size of 10 GB and ReadWriteMany access mode
export volsize="10Gi"
for volume in pv{26..50} ; do
cat << EOF > /root/pvs/${volume}
{
  "apiVersion": "v1",
  "kind": "PersistentVolume",
  "metadata": {
    "name": "${volume}"
  },
  "spec": {
    "capacity": {
        "storage": "${volsize}"
    },
    "accessModes": [ "ReadWriteMany" ],
    "nfs": {
        "path": "/srv/nfs/user-vols/${volume}",
        "server": "support1.${GUID}.internal"
    },
    "persistentVolumeReclaimPolicy": "Retain"
  }
}
EOF
echo "Created def file for ${volume}";
done;

cat /root/pvs/* | oc create -f -

# Create tasks-dev tasks-test tasks-prod projects
oc new-project tasks-dev --description="Development Environment" --display-name="Tasks - Dev"
oc new-project tasks-test --description="Testing Environment" --display-name="Test - Dev"
oc new-project tasks-prod --description="Production Environment" --display-name="Prod - Dev"
