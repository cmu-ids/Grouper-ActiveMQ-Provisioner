FROM jtgasper3/389ds-basic

MAINTAINER jgasper@unicon.net

COPY users.ldif /
COPY schema.ldif /

RUN start-dirsrv \
    && sleep 2 \
    && ldapmodify -H ldap:/// -f /schema.ldif -x -D "cn=Directory Manager" -w password \
    && ldapadd -H ldap:/// -f /users.ldif -x -D "cn=Directory Manager" -w password \
    && stop-dirsrv

CMD start-dirsrv && tail -F /var/log/dirsrv/slapd-dir/access
