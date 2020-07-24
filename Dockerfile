FROM nginx:mainline-alpine-perl
RUN    apk update \
    && apk upgrade \
    && apk add git git-gitweb git-daemon openssh fcgiwrap perl-cgi spawn-fcgi rsync
RUN    sed -i 's/#UseDNS no/UseDNS no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

COPY service.sh /service.sh
COPY sync.sh /sync.sh
CMD ["/service.sh"]
