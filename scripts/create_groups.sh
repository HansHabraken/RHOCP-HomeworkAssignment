oc login -u system:admin

oc adm groups new alphacorp amy andrew
oc adm groups new betacorp betty brian

oc label group/alphacorp client=alpha
oc label group/betacorp client=beta
