FROM nginx:mainline-alpine-perl
RUN    apk update \
    && apk upgrade \
    && apk add git git-gitweb git-daemon openssh fcgiwrap perl-cgi spawn-fcgi rsync highlight
RUN    sed -i 's/#UseDNS no/UseDNS no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config


RUN ln -sf /dev/stdout /var/log/nginx/access.log && ln -sf /dev/stderr /var/log/nginx/error.log

COPY service.sh /service.sh
COPY sync.sh /sync.sh
COPY init.template /init.template

CMD ["/service.sh"]

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD nc -vz -w 2 localhost 80 && nc -vz -w 2 localhost 22 || exit 1
