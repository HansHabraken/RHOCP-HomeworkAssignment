
ansible master -b -a "htpasswd -b /etc/origin/master/htpasswd amy 1234"
ansible master -b -a "htpasswd -b /etc/origin/master/htpasswd andrew 1234"
ansible master -b -a "htpasswd -b /etc/origin/master/htpasswd brian 1234"
ansible master -b -a "htpasswd -b /etc/origin/master/htpasswd betty 1234"
