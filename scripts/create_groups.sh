oc login -u system:admin

oc adm groups new alphacorp amy andrew
oc adm groups new betacorp betty brian

oc labels group/alphacorp client=alpha
oc labels group/betacorp client=beta
