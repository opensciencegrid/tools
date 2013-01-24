#!/bin/bash

# Fermicloud startup script for common packages
#  Created by Doug Strain 2012
#  
# For use in installing and configuring basic installs
# of storage packages on clean machines (e.g. fermicloud VMs)
#   NOTE: Before running, verify REPO and SERVER vars below!!

# Usage: ./osg_install [package-name]
#   - if package-name is left out, script will install osg/epel repos
# Valid Package names:
# - xrootd: basic one-server xrootd
# - xrootd-lcmaps: xrootd with GSI auth [may be a bit buggy]
# - gridftp: gridftp with gums
# - bestman: bestman on top of local filesystem
# - bestmanxrootd, bestmanhadoop: bestman on top of xrootd/hadoop (set SERVER)
# - rsv: RSV with storage probes (set SERVER to bestman2 server)
# - hadoop: Hadoop-0.20 HDFS (for both data/namenode).  Set SERVER to namenode.
# - hadoop200: Hadoop 2.0.0 HDFS (both data/namenode).  Set SERVER to namenode.
# - hadoop200ftp: Gridftp on top of Hadoop 2.0.0
# - hadoop200ftp: BestMan2 on top of Hadoop 2.0.0
# - unittest: osg-test framework
# - gums: GUMS server.  Doesn't set up DB right, so have to re-run scripts

# Change this to the repo you wish to install from 
#  (eg "osg", "osg-testing", "osg-development", or "osg-minefield")
REPO="osg-development"

# For multi server installs, this points to the server
#   - For hadoop*, this should be the namenode
#   - For bestman/xrootd, this should be the xrootd redirector
SERVER='fermicloud075.fnal.gov'




HOSTNAME=`hostname`


#MODIFY THESE for hadoop
# NOTE: HADOOP hostnames must match hostname -s (fermicloud034)
HADOOP_NAMENODE=$SERVER
HADOOP_SECONDARY_NAMENODE="fermicloud123"

#maybe modify these
HADOOP_CHECKPOINT_DIRS="/data/hadoop/datadir"
HADOOP_CHECKPOINT_PERIOD="1200"
HADOOP_DATADIR="/data/hadoop/datadir"
HADOOP_REPLICATION_DEFAULT="1"
HADOOP_MNT="/mnt/hadoop"


echo "Installing repos..."
rpm -Uvh http://dl.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm
yum -y install yum-priorities
rpm -Uvh http://repo.grid.iu.edu/osg-release-latest.rpm

echo "Creating users..."
getent passwd osg >/dev/null || useradd -g osg osg
getent passwd fnalgrid >/dev/null || useradd -g fnalgrid fnalgrid


if [[ "$1" == xrootd* ]]; then
	echo "Installing xrootd-server";
	yum install -y --enablerepo=$REPO xrootd-server
	service xrootd setup
	service xrootd start
	xrdcp /bin/sh root://localhost:1094//tmp/first_test
	ls -la /tmp/first_test
	if [ 'xrootd-lcmaps' == "$1" ]; then
		yum install -y --enablerepo=$REPO osg-ca-certs fetch-crl
		fetch-crl
		yum install -y --enablerepo=$REPO xrootd-lcmaps
		sed -i "s/red-auth.unl.edu:8443/gums.fnal.gov:8443/" /etc/xrootd/lcmaps.cfg
		sed -i "s/\/tmp/\/data\/xrootdfs/" /etc/xrootd/xrootd-clustered.cfg
		mkdir /etc/grid-security/xrd
		cp /etc/grid-security/hostkey.pem /etc/grid-security/xrd/xrdkey.pem
		cp /etc/grid-security/hostcert.pem /etc/grid-security/xrd/xrdcert.pem
		chown -R xrootd:xrootd /etc/grid-security/xrd/
		chmod 400 /etc/grid-security/xrd/xrdkey.pem
		echo "cms.space min 2g 5g" >> /etc/xrootd/xrootd-clustered.cfg
		echo "xrootd.seclib /usr/lib64/libXrdSec.so" >> /etc/xrootd/xrootd-clustered.cfg
		echo "sec.protocol /usr/lib64 gsi -certdir:/etc/grid-security/certificates -cert:/etc/grid-security/xrd/xrdcert.pem -key:/etc/grid-security/xrd/xrdkey.pem -crl:3 -authzfun:libXrdLcmaps.so -authzfunparms:--osg,--lcmapscfg,/etc/xrootd/lcmaps.cfg,--loglevel,0|useglobals --gmapopt:2 --gmapto:0" >> /etc/xrootd/xrootd-clustered.cfg
        	echo "acc.authdb /etc/xrootd/auth_file" >> /etc/xrootd/xrootd-clustered.cfg
        	echo "ofs.authorize" >> /etc/xrootd/xrootd-clustered.cfg
		echo "u * /data/xrootdfs lr" > /etc/xrootd/auth_file
		echo "u = /data/xrootdfs/@=/ a" >>/etc/xrootd/auth_file
		echo "u xrootd /data/xrootdfs a" >>/etc/xrootd/auth_file
		mkdir -p /data/xrootdfs/osg
		chown -R xrootd:xrootd /data/xrootdfs
		service xrootd stop
		service xrootd start
		service cmsd start
	fi
fi

if [ 'gridftp' == "$1" ]; then
	echo "Installing stand-alone gridftp";
	yum -y --enablerepo=$REPO install osg-gridftp
	sed -i 's/\#.*globus_mapping/globus_mapping/' /etc/grid-security/gsi-authz.conf
	sed -i 's/yourgums.yourdomain/gums.fnal.gov/' /etc/lcmaps.db
fi


if [ 'bestman' == "$1" ]; then
	echo "Installing stand-alone BeStMan";
	yum -y --enablerepo=$REPO install osg-se-bestman
	sed -i 's/\#.*globus_mapping/globus_mapping/' /etc/grid-security/gsi-authz.conf
	sed -i 's/yourgums.yourdomain/gums.fnal.gov/' /etc/lcmaps.db
	mkdir /etc/grid-security/bestman
	cp /etc/grid-security/hostkey.pem /etc/grid-security/bestman/bestmankey.pem
	cp /etc/grid-security/hostcert.pem /etc/grid-security/bestman/bestmancert.pem
	chown -R bestman:bestman /etc/grid-security/bestman/
	sed -i 's/Defaults.*requiretty/#Defaults requiretty/' /etc/sudoers
	echo "Cmnd_Alias SRM_CMD = /bin/rm, /bin/mkdir, /bin/rmdir, /bin/mv, /bin/ls" >> /etc/sudoers
	echo 'Runas_Alias SRM_USR = ALL, !root' >> /etc/sudoers
	echo "bestman ALL=(SRM_USR) NOPASSWD:SRM_CMD" >> /etc/sudoers
	sed -i 's/BESTMAN_GUMSCERTPATH=.*/BESTMAN_GUMSCERTPATH=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
	sed -i 's/BESTMAN_GUMSKEYPATH=.*/BESTMAN_GUMSKEYPATH=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
	sed -i 's/CertFileName=.*/CertFileName=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
	sed -i 's/KeyFileName=.*/KeyFileName=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
	#sed -i 's/GUMSserviceURL=.*/GUMSserviceURL=https:\/\/gums.fnal.gov:8443\/gums\/services\/GUMSAuthorizationServicePort/' /etc/bestman2/conf/bestman2.rc
	echo "GUMSserviceURL=https://gums.fnal.gov:8443/gums/services/GUMSXACMLAuthorizationServicePort" >> /etc/bestman2/conf/bestman2.rc
	echo "localPathListAllowed=/tmp" >> /etc/bestman2/conf/bestman2.rc
	echo "supportedProtocolList=gsiftp://$HOSTNAME" >> /etc/bestman2/conf/bestman2.rc
fi

if [ 'bestmanxrootd' == "$1" ]; then
        echo "Installing BeStMan-gateway Xrootd";
        yum -y --enablerepo=$REPO install osg-se-bestman-xrootd.x86_64
        sed -i 's/\#.*globus_mapping/globus_mapping/' /etc/grid-security/gsi-authz.conf
        sed -i 's/yourgums.yourdomain/gums.fnal.gov/' /etc/lcmaps.db
        mkdir /etc/grid-security/bestman
        cp /etc/grid-security/hostkey.pem /etc/grid-security/bestman/bestmankey.pem
        cp /etc/grid-security/hostcert.pem /etc/grid-security/bestman/bestmancert.pem
        chown -R bestman:bestman /etc/grid-security/bestman/
        sed -i 's/Defaults.*requiretty/#Defaults requiretty/' /etc/sudoers
        echo "Cmnd_Alias SRM_CMD = /bin/rm, /bin/mkdir, /bin/rmdir, /bin/mv, /bin/ls" >> /etc/sudoers
        echo 'Runas_Alias SRM_USR = ALL, !root' >> /etc/sudoers
        echo "bestman ALL=(SRM_USR) NOPASSWD:SRM_CMD" >> /etc/sudoers
        sed -i 's/BESTMAN_GUMSCERTPATH=.*/BESTMAN_GUMSCERTPATH=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/BESTMAN_GUMSKEYPATH=.*/BESTMAN_GUMSKEYPATH=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/CertFileName=.*/CertFileName=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/KeyFileName=.*/KeyFileName=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
        #sed -i 's/GUMSserviceURL=.*/GUMSserviceURL=https:\/\/gums.fnal.gov:8443\/gums\/services\/GUMSAuthorizationServicePort/' /etc/bestman2/conf/bestman2.rc
	echo "GUMSserviceURL=https://gums.fnal.gov:8443/gums/services/GUMSXACMLAuthorizationServicePort" >> /etc/bestman2/conf/bestman2.rc
        echo "localPathListAllowed=/tmp;/mnt/xrootd" >> /etc/bestman2/conf/bestman2.rc
        echo "supportedProtocolList=gsiftp://$HOSTNAME" >> /etc/bestman2/conf/bestman2.rc
	sed -i "s/XROOTD_VMP=.*/XROOTD_VMP=\"$SERVER:1094:\/mnt\/xrootd=\/tmp\"/" /etc/sysconfig/gridftp.conf.d/xrootd-dsi-environment 
	echo "xrootdfs                /mnt/xrootd              fuse    rdr=xroot://$SERVER:1094//tmp/,uid=xrootd 0 0" >> /etc/fstab
        mkdir /mnt/xrootd
	mount /mnt/xrootd
fi

if [ 'bestmanhadoop' == "$1" ]; then
	# have not tested this yet
        echo "Installing BeStMan gateway - hadoop";
        yum -y --enablerepo=$REPO --enablerepo=epel install osg-ca-certs fetch-crl osg-gridftp-hdfs hadoop-0.20-osg hadoop-0.20-fuse bestman2-server
        sed -i 's/\#.*globus_mapping/globus_mapping/' /etc/grid-security/gsi-authz.conf
        sed -i 's/yourgums.yourdomain/gums.fnal.gov/' /etc/lcmaps.db
        mkdir /etc/grid-security/bestman
        cp /etc/grid-security/hostkey.pem /etc/grid-security/bestman/bestmankey.pem
        cp /etc/grid-security/hostcert.pem /etc/grid-security/bestman/bestmancert.pem
        chown -R bestman:bestman /etc/grid-security/bestman/
        sed -i 's/Defaults.*requiretty/#Defaults requiretty/' /etc/sudoers
        echo "Cmnd_Alias SRM_CMD = /bin/rm, /bin/mkdir, /bin/rmdir, /bin/mv, /bin/ls" >> /etc/sudoers
        echo 'Runas_Alias SRM_USR = ALL, !root' >> /etc/sudoers
        echo "bestman ALL=(SRM_USR) NOPASSWD:SRM_CMD" >> /etc/sudoers
        sed -i 's/BESTMAN_GUMSCERTPATH=.*/BESTMAN_GUMSCERTPATH=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/BESTMAN_GUMSKEYPATH=.*/BESTMAN_GUMSKEYPATH=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/CertFileName=.*/CertFileName=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/KeyFileName=.*/KeyFileName=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/GUMSserviceURL=.*/GUMSserviceURL=https:\/\/gums.fnal.gov:8443\/gums\/services\/GUMSAuthorizationServicePort/' /etc/bestman2/conf/bestman2.rc
	echo "GUMSserviceURL=https://gums.fnal.gov:8443/gums/services/GUMSXACMLAuthorizationServicePort" >> /etc/bestman2/conf/bestman2.rc
        echo "localPathListAllowed=/tmp;/mnt/hadoop" >> /etc/bestman2/conf/bestman2.rc
        echo "supportedProtocolList=gsiftp://$HOSTNAME" >> /etc/bestman2/conf/bestman2.rc
        sed -i "s/HADOOP_NAMENODE=.*/HADOOP_NAMENODE=$SERVER/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_CHECKPOINT_DIRS=.*/HADOOP_CHECKPOINT_DIRS=\/home\/hadoop/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_DATADIR=.*/HADOOP_DATADIR=\/home\/hadoop/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_REPLICATION_DEFAULT=.*/HADOOP_REPLICATION_DEFAULT=2/" /etc/sysconfig/hadoop
	mkdir -p /mnt/hadoop
        echo "hdfs# /mnt/hadoop fuse server=$SERVER,port=9000,rdbuffer=32768,allow_other 0 0" >> /etc/fstab
        mount /mnt/hadoop
	service hadoop-firstboot start
fi



if [ 'rsv' == "$1" ]; then
	yum -y --enablerepo=$REPO install rsv
	mkdir -p /etc/grid-security/rsv
	cp /etc/grid-security/hostcert.pem /etc/grid-security/rsv/rsvcert.pem
	cp /etc/grid-security/hostkey.pem /etc/grid-security/rsv/rsvkey.pem
	scp gw014k0:/tmp/x509up_u44678 /tmp/rsv_proxy
	chown rsv:rsv /etc/grid-security/rsv
	chown rsv:rsv /etc/grid-security/rsv/rsvcert.pem
	chown rsv:rsv /etc/grid-security/rsv/rsvkey.pem
	chown rsv:rsv /tmp/rsv_proxy
	sed -i "s/enable_gratia = .*/enable_gratia = False/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/service_cert = .*/service_cert = \/etc\/grid-security\/rsv\/rsvcert.pem/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/service_key = .*/service_key = \/etc\/grid-security\/rsv\/rsvkey.pem/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/service_proxy = .*/service_proxy = \/tmp\/rsv_proxy/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/;gridftp_hosts = .*/gridftp_hosts = $SERVER/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/gridftp_dir = .*/gridftp_dir = \/tmp/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/srm_hosts = .*/srm_hosts = $SERVER/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/srm_dir = .*/srm_dir = \/tmp/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/srm_webservice_path = .*/srm_webservice_path = srm\/v2\/server/" /etc/osg/config.d/30-rsv.ini
	sed -i "s/Listen 80/Listen 9000/" /etc/http/conf/httpd.conf
	sed -i "s/ Indexes/ \-Indexes/" /etc/httpd/conf/httpd.conf
	sed -i "s/Order allow,deny/Order deny,allow/" /etc/httpd/conf/httpd.conf
	sed -i "s/^\s*Allow from all/Deny from all\nAllow from 131.225\nAllow from 2620:6a::\/48/" /etc/httpd/conf/httpd.conf
	configure-osg -v
	configure-osg -c
	service httpd start
	service condor-cron start
	service rsv start
fi

HADOOP_MNT_ESCAPED=`echo $HADOOP_MNT |  sed 's/\//\\\\\//g'`
HADOOP_CHECKPOINT_DIRS_ESCAPED=`echo $HADOOP_CHECKPOINT_DIRS |  sed 's/\//\\\\\//g'`
HADOOP_DATADIR_ESCAPED=`echo $HADOOP_DATADIR |  sed 's/\//\\\\\//g'`

if [ 'hadoop' == "$1" ]; then
	yum -y --enablerepo=$REPO install hadoop-0.20-osg hadoop-0.20-fuse
        #modify sysconfig
        sed -i "s/HADOOP_NAMENODE=.*/HADOOP_NAMENODE=$HADOOP_NAMENODE/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_SECONDARY_NAMENODE=.*/HADOOP_SECONDARY_NAMENODE=$HADOOP_SECONDARY_NAMENODE/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_CHECKPOINT_DIRS=.*/HADOOP_CHECKPOINT_DIRS=$HADOOP_CHECKPOINT_DIRS_ESCAPED/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_CHECKPOINT_PERIOD=.*/HADOOP_CHECKPOINT_PERIOD=$HADOOP_CHECKPOINT_PERIOD/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_DATADIR=.*/HADOOP_DATADIR=$HADOOP_DATADIR_ESCAPED/" /etc/sysconfig/hadoop
        sed -i "s/^HADOOP_REPLICATION_DEFAULT=.*/HADOOP_REPLICATION_DEFAULT=$HADOOP_REPLICATION_DEFAULT/" /etc/sysconfig/hadoop

        mkdir -p $HADOOP_CHECKPOINT_DIRS
        mkdir -p $HADOOP_DATADIR

        service hadoop-firstboot start
        #Optional
        sed -i 's/10000000000/100000000/' /etc/hadoop/conf/hdfs-site.xml

        chkconfig hadoop on
        service hadoop start
fi



#Not sure if this is needed anymore
if [ 'fuse' == "$1" ]; then
        #fuse
        yum --enablerepo=$REPO install fuse-libs
        yum --enablerepo=$REPO install fuse
        modprobe fuse
        yum --enablerepo=$REPO install hadoop-fuse
        echo "hdfs# $HADOOP_MNT fuse server=$HADOOP_NAMENODE,port=9000,rdbuffer=32768,allow_other 0 0" >> /etc/fstab

        mkdir -p $HADOOP_MNT
        mount $HADOOP_MNT
fi

if [ 'unittest' == "$1" ]; then
        yum install -y subversion
	wget --quiet http://vdt.cs.wisc.edu/native/bootstrap-osg-test
	chmod 0755 bootstrap-osg-test
	./bootstrap-osg-test testing
        svn co https://vdt.cs.wisc.edu/svn/software/osg-test
        ln -s osg-test/trunk/osgtest/tests tests
        ln -s /usr/lib/python2.4/site-packages/osgtest/tests tests/libtestdir
        echo "To run tests: osg-test -vai PACKAGE -r osg-testing"
fi

if [ 'hadoop200' == "$1" ]; then
        if [[ `hostname` == "$SERVER" ]];
        then
        yum --enablerepo=$REPO install -y osg-se-hadoop-namenode
        else
        yum --enablerepo=$REPO install -y osg-se-hadoop-datanode
        fi
        sed -i '9aexclude=hadoop\*' /etc/yum.repos.d/osg.repo
        mkdir -p /data/hadoop
        mkdir -p /data/scratch
        mkdir -p /data/checkpoint
        chown -R hdfs:hdfs /data
        sed -i "s/NAMENODE/$SERVER/" /etc/hadoop/conf.osg/core-site.xml
        sed -i "s/NAMENODE/$SERVER/" /etc/hadoop/conf.osg/hdfs-site.xml
        cp /etc/hadoop/conf.osg/core-site.xml /etc/hadoop/conf
        cp /etc/hadoop/conf.osg/hdfs-site.xml /etc/hadoop/conf
        touch /etc/hosts_exclude

        if [[ `hostname` == "$SERVER" ]];
        then
        su - hdfs -c "hadoop namenode -format"
        service hadoop-hdfs-namenode start
        else
        service hadoop-hdfs-datanode start
        fi
fi

if [ 'hadoop200ftp' == "$1" ]; then
        yum --enablerepo=$REPO install -y osg-se-hadoop-gridftp
        sed -i '9aexclude=hadoop\*' /etc/yum.repos.d/osg.repo
        sed -i "s/NAMENODE/$SERVER/" /etc/hadoop/conf.osg/core-site.xml
        sed -i "s/NAMENODE/$SERVER/" /etc/hadoop/conf.osg/hdfs-site.xml
        cp /etc/hadoop/conf.osg/core-site.xml /etc/hadoop/conf
        cp /etc/hadoop/conf.osg/hdfs-site.xml /etc/hadoop/conf
        echo "hadoop-fuse-dfs# /mnt/hadoop fuse server=$SERVER,port=9000,rdbuffer=131072,allow_other 0 0" >> /etc/fstab
        mkdir /mnt/hadoop
        mount /mnt/hadoop
        sed -i 's/\#.*globus_mapping/globus_mapping/' /etc/grid-security/gsi-authz.conf
        sed -i 's/yourgums.yourdomain/gums.fnal.gov/' /etc/lcmaps.db
        service globus-gridftp-server start
fi

if [ 'hadoop200bestman' == "$1" ]; then
        yum --enablerepo=$REPO install -y osg-se-hadoop-srm
        sed -i '9aexclude=hadoop\*' /etc/yum.repos.d/osg.repo
        mkdir /etc/grid-security/bestman
        cp /etc/grid-security/hostkey.pem /etc/grid-security/bestman/bestmankey.pem
        cp /etc/grid-security/hostcert.pem /etc/grid-security/bestman/bestmancert.pem
        chown -R bestman:bestman /etc/grid-security/bestman/
        sed -i 's/Defaults.*requiretty/#Defaults requiretty/' /etc/sudoers
        echo "Cmnd_Alias SRM_CMD = /bin/rm, /bin/mkdir, /bin/rmdir, /bin/mv, /bin/ls" >> /etc/sudoers
        echo 'Runas_Alias SRM_USR = ALL, !root' >> /etc/sudoers
        echo "bestman ALL=(SRM_USR) NOPASSWD:SRM_CMD" >> /etc/sudoers
        sed -i 's/BESTMAN_GUMSCERTPATH=.*/BESTMAN_GUMSCERTPATH=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/BESTMAN_GUMSKEYPATH=.*/BESTMAN_GUMSKEYPATH=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/CertFileName=.*/CertFileName=\/etc\/grid-security\/bestman\/bestmancert.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/KeyFileName=.*/KeyFileName=\/etc\/grid-security\/bestman\/bestmankey.pem/' /etc/bestman2/conf/bestman2.rc
        sed -i 's/GUMSserviceURL=.*/GUMSserviceURL=https:\/\/gums.fnal.gov:8443\/gums\/services\/GUMSAuthorizationServicePort/' /etc/bestman2/conf/bestman2.rc
        echo "GUMSserviceURL=https://gums.fnal.gov:8443/gums/services/GUMSXACMLAuthorizationServicePort" >> /etc/bestman2/conf/bestman2.rc
        echo "localPathListAllowed=/tmp;/mnt/hadoop" >> /etc/bestman2/conf/bestman2.rc
        echo "supportedProtocolList=gsiftp://$HOSTNAME" >> /etc/bestman2/conf/bestman2.rc
        sed -i "s/NAMENODE/$SERVER/" /etc/hadoop/conf.osg/core-site.xml
        sed -i "s/NAMENODE/$SERVER/" /etc/hadoop/conf.osg/hdfs-site.xml
        cp /etc/hadoop/conf.osg/core-site.xml /etc/hadoop/conf
        cp /etc/hadoop/conf.osg/hdfs-site.xml /etc/hadoop/conf
        echo "hadoop-fuse-dfs# /mnt/hadoop fuse server=$SERVER,port=9000,rdbuffer=131072,allow_other 0 0" >> /etc/fstab
        mkdir /mnt/hadoop
        mount /mnt/hadoop
        echo "Don't forget to change the gsiftp host if different from current machine."
fi


if [ 'gums' == "$1" ]; then
        yum --enablerepo=$REPO install -y osg-gums
        yum --enablerepo=$REPO install -y fetch-crl
	fetch-crl
	/var/lib/trustmanager-tomcat/configure.sh 
	/sbin/service mysqld start
	/usr/bin/gums-setup-mysql-database --user gums --host localhost:3306 --password bogomips
	/usr/bin/mysql_secure_installation
	gums-add-mysql-admin '/DC=org/DC=doegrids/OU=People/CN=Doug Strain 834323'
	cp /etc/gums/gums.config.template /etc/gums/gums.config
	sed -i 's/@USER@/gums/' /etc/gums/gums.config
	sed -i 's/@PASSWORD@/bogomips/' /etc/gums/gums.config
	sed -i "s/@SERVER@/localhost:3306/" /etc/gums/gums.config
	sed -i "s/@DOMAINNAME@/fnal.gov/" /etc/gums/gums.config

	#symlinks don't work
	mv /etc/grid-security/http/httpcert.pem /etc/grid-security/http/linkcert.pem
	mv /etc/grid-security/http/httpkey.pem /etc/grid-security/http/linkkey.pem
	cp /etc/grid-security/http/linkcert.pem /etc/grid-security/http/httpcert.pem
	cp /etc/grid-security/http/linkkey.pem /etc/grid-security/http/httpkey.pem
	chown tomcat:tomcat /etc/grid-security/http/httpcert.pem
	chown tomcat:tomcat /etc/grid-security/http/httpkey.pem

	sed -i 's/<Context/<Context allowLinking=\"true\"/' /etc/tomcat6/context.xml
	/sbin/service mysqld start
	/sbin/service tomcat5 start
fi

