FROM centos:centos7

RUN yum -y install epel-release \
    && yum -y update \
    && yum -y install cpanminus gcc openssl-devel perl \
    && yum -y clean all \
    && cpanm -f Digest::MD5 \
    && cpanm JSON \
    && cpanm Log::Log4perl \
    && cpanm Net::DNS \
    && cpanm Net::LDAP::Entry \
    && cpanm Net::Stomp \
    && yum -y remove gcc

COPY temp/amq_ldap_provisioner/ /opt/amq_ldap_provisioner/
COPY configuration.pl /opt/amq_ldap_provisioner/
COPY log4perl.conf /opt/amq_ldap_provisioner/conf/

WORKDIR /opt/amq_ldap_provisioner

RUN mkdir logs

CMD perl main.pl
