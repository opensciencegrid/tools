#!/bin/bash
#set -e

usage () {
  echo "usage: $(basename "$0") gums.template"
  echo
  echo "must be run as root on a fermi vm."
  echo
  echo "attempts to install and set up a gums instance using a provided"
  echo "gums.template file, and use wget to trigger the web interface to"
  echo "save it in the new format.  the script does some necessary cleanup"
  echo "on the converted file and outputs gums.config.template in the"
  echo "current directory."
  echo
  echo "the final result should be diffed against the previous version"
  echo "to verify correctness."
  exit
}

fail () { echo "$@" >&2; exit 1; }

on_err () {
  echo ::: ERROR :::
  read -p "exit/continue/shell? [E/c/s]" cancel
  case $cancel in
    c* ) ;;
    s* ) echo "exit shell to resume script..."
         bash
         read -p "resume script? [Y/n] " resume
         case $resume in
           n* ) echo "quitting..."; exit ;;
           *  ) echo "resuming..."
         esac ;;
     * ) echo "quitting..."; exit ;;
  esac
}

SECTION () {
  echo
  echo "*****   $*   *****"
  echo
}

[[ -f $1 ]] || usage
gums_template=$1

[[ $USER = root ]] || fail "please run as root"
[[ $HOSTNAME = *.fnal.gov ]] || fail "please run on a fermi vm"

trap on_err ERR

case $(uname -r) in
  *.el5 | *.el5.* ) el=5; epr=5-4 ;;
  *.el6 | *.el6.* ) el=6; epr=6-8 ;;
      * ) echo Unrecognized EL version; exit 1 ;;
esac

SECTION doing yum installs

yum clean -q --enablerepo=\* expire-cache
rpm -qa | grep '^java-1\.6\.0-openjdk' | xargs -r yum remove -q -y || :
yum install -q -y osg-java7-\*compat\*
yum install -q -y osg-ca-certs osg-gums
yum install -q -y globus-proxy-utils krb5-fermi-getcert
yum install -q -y links /usr/bin/xxd

SECTION configuring trustmanager-tomcat

/var/lib/trustmanager-tomcat/configure.sh --force

SECTION starting mysqld

service mysqld start

SECTION setting up fermi proxy

GUMSDBPW=GUMSDBPW
#UNPRIV_USER=edquist
#CERT_PW=abc123
#DN="/DC=com/DC=DigiCert-Grid/O=Open Science Grid/OU=People/CN=Carl Edquist 1013"
UNPRIV_USER=$(klist | awk '/Default principal:/ {print $NF}' | cut -d@ -f1)
CERT_PW=$(dd if=/dev/urandom bs=1 count=16 2>/dev/null | xxd -p)
DN=$(
ssh $UNPRIV_USER@$HOSTNAME "
  . /etc/bashrc
  set -e
  echo \"$CERT_PW\" | /usr/krb5/bin/get-cert >&2
# echo \"$CERT_PW\" | grid-proxy-init -pwstdin >&2
  echo | openssl pkcs12 -in /tmp/x509up_u\$UID.p12 -out /tmp/cert\$UID.crt.pem \
                        -clcerts -nokeys -password stdin >&2

  echo | openssl pkcs12 -in /tmp/x509up_u\$UID.p12 -out /tmp/cert\$UID.key.pem \
                        -nocerts -nodes -password stdin >&2

  openssl x509 -in /tmp/x509up_u\$UID -noout -subject \
  | sed 's/^subject= //; s,/CN=[0-9]*$,,'
")

SECTION setting up gums mysql db

/usr/bin/gums-setup-mysql-database --user gums --host localhost:3306 \
    --password "$GUMSDBPW" --noprompt

#echo yes | /usr/bin/gums-add-mysql-admin "$DN"

# break open gums-add-mysql-admin script so we can avoid typing:

sed -e "s%@ADMINDN@%$DN%g" /usr/lib/gums/sql/addAdmin.mysql \
| mysql -u gums -p"$GUMSDBPW"

# should be tomcat:tomcat owned already...
cp "$gums_template" /etc/gums/gums.config

sed -i.bak "s/@SERVER@/$HOSTNAME:3306/;
            s/GUMS_1_1/GUMS_1_3/;
            s/@USER@/gums/;
            s/@PASSWORD@/$GUMSDBPW/;
#           s/@DOMAINNAME@/wisc.edu/" /etc/gums/gums.config

mysql -u root mysql <<EOF
GRANT ALL ON GUMS_1_3.* TO 'gums'@'$HOSTNAME' IDENTIFIED BY '$GUMSDBPW';
GRANT ALL ON GUMS_1_3.* TO 'gums'@'localhost' IDENTIFIED BY '$GUMSDBPW';
FLUSH PRIVILEGES;
EOF

SECTION "copying host certs for tomcat use"

cd /etc/grid-security
mv http/ http-
mkdir http
cp host*.pem http/
rename host http http/host*.pem
chown -R tomcat:tomcat http
cd - >/dev/null

SECTION "running fetch-crl (may take a while...)"

case $el in
  5) /usr/sbin/fetch-crl3 || :
     /sbin/service tomcat5 start ;;
  6) /usr/sbin/fetch-crl || :
     /sbin/service tomcat6 start ;;
esac

SECTION "waiting for gums to start up... (10s)"

sleep 10

echo "connect to https://$HOSTNAME:8443/gums/"
echo "go to User Groups, edit one, click [Save]"
echo
echo "(will try to do this automatically with wget...)"

SECTION saving config with wget

ssh $UNPRIV_USER@$HOSTNAME '
  save_url="https://$HOSTNAME:8443/gums/userGroups.jsp?command=save&originalCommand=edit&name=LIGO&description=&ug_type=voms&vOrg=ligo&url=&nVOMS=true&matchFQAN=vo&vogroup=%2FLIGO&role=&access=read+self"
  wget --certificate /tmp/cert$UID.crt.pem \
       --private-key /tmp/cert$UID.key.pem \
       --no-check-certificate  "$save_url" \
       -O /tmp/save.html
'

if ! grep -o 'User group has been saved.' /tmp/save.html; then
  echo "... not sure if the save worked, inspect with: links /tmp/save.html"
fi

SECTION fixing gums.config

# cleanup after saving...
sed "s%sslCAFiles=''%sslCAFiles='/etc/grid-security/certificates\/*.0'%;
     s%/services/VOMSAdmin%%;
     /hibernate.connection.username=/s%'[^']*'%'@USER@'%;
     /hibernate.connection.url=/s%//[^/]*/%//@SERVER@/%;
     /hibernate.connection.password=/s%'[^']*'%'@PASSWORD@'%;
" /etc/gums/gums.config > gums.config.template

echo "wrote gums.config.template  (now diff against previous version...)"

