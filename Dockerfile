FROM alpine:3.7

RUN apk add --no-cache bash openssh-client \
                       duplicity py2-pip py-setuptools py2-paramiko py2-pexpect \
                       rsync tar gzip bzip2 xz \
                       postgresql mysql-client \
 && pip2 install fasteners
#RUN apk add duply

COPY entrypoint.sh /usr/local/bin/backup

ENV HOME=/root

VOLUME ["/keys", "/archive", "/root/.ssh", "/root/.gnupg"]

ENTRYPOINT ["/usr/local/bin/backup"]
