FROM unicon/grouper-demo:2.3.0

ADD temp/cmuConsumer-1.0.tar.gz /tmp

RUN cp /tmp/lib/grouper/* /opt/grouper.apiBinary-2.3.0/lib/custom/

COPY testInit.gsh /
COPY conf/ /opt/grouper.apiBinary-2.3.0/conf/

RUN set -x; \
    service mysql start \
    && service slapd start \
    && cd /opt/grouper.apiBinary-2.3.0/ \
    && bin/gsh /testInit.gsh \
    && rm /testInit.gsh
    