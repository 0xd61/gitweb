#!/usr/bin/env sh
USER=git
ENV=/.env
NGINX_CONF=/etc/nginx/conf.d/default.conf
GITWEB_CONF=/etc/gitweb.conf
SSHD_CONF=/etc/ssh/sshd_config
SERVER_ROOT=/jail
SERVER_DIR=${SERVER_ROOT}/git
SYNC_SCRIPT=/sync.sh

# TODO(dgl): to load config on each loop
# we have to check for changes and update the
# authorized_keys file.
. /.env

# ---- Setup git ----
id -u $USER  &>/dev/null || adduser $USER -D
# need to make this call to enable pubkey ssh auth
passwd -d $USER
su $USER -c sh << EOC

#[ -f ~/.ssh/id_rsa ] || ssh-keygen -f ~/.ssh/id_rsa -b 2048 -t rsa -q -N ""

[ -d ~/.ssh ] || mkdir -p /home/$USER/.ssh
echo "${PRIVATE_KEY}" > /home/$USER/.ssh/id_rsa
echo "${AUTHORIZED_KEYS}" > /home/$USER/.ssh/authorized_keys
echo "${BASIC_AUTH}" > /home/$USER/.htpasswd
cat << EOF > ~/.ssh/config
Host *
  IdentityFile ~/.ssh/id_rsa
  StrictHostKeyChecking no
EOF

chmod 600 /home/$USER/.ssh/id_rsa
chmod 600 /home/$USER/.ssh/authorized_keys
chmod 600 /home/$USER/.htpasswd
EOC

# ---- Setup chroot for git ----
mkdir -p                      $SERVER_ROOT/dev
mkdir -p                      $SERVER_ROOT/lib
mkdir -p                      $SERVER_ROOT/bin
mkdir -p                      $SERVER_ROOT/proc
mkdir -p                      $SERVER_ROOT/usr/bin
mkdir -p                      $SERVER_ROOT/usr/lib
mknod -m 666                  $SERVER_ROOT/dev/null c 1 3
mknod -m 444                  $SERVER_ROOT/dev/random c 1 8
mknod -m 444                  $SERVER_ROOT/dev/urandom c 1 9
cp /bin/busybox               $SERVER_ROOT/bin
cp /usr/bin/git               $SERVER_ROOT/usr/bin
cp /usr/bin/git-receive-pack  $SERVER_ROOT/usr/bin
cp /usr/bin/git-upload-pack   $SERVER_ROOT/usr/bin
cp /usr/bin/git-receive-pack  $SERVER_ROOT/usr/bin
cp /lib/ld-musl*              $SERVER_ROOT/lib
cp /usr/lib/libpcre2*         $SERVER_ROOT/usr/lib
cp /usr/lib/libz*                 $SERVER_ROOT/lib
ln $SERVER_ROOT/bin/busybox   $SERVER_ROOT/bin/ash
ln $SERVER_ROOT/bin/busybox   $SERVER_ROOT/bin/sh
mount -t proc proc            $SERVER_ROOT/proc

# TODO(dgl): fix remote: warning: unable to access '/root/.config/git/attributes': Permission denied
# on git clone via http

#cat $APACHE_CONFIG_DIR/gitServer.xml >> $APACHE_CONFIG_DIR/conf/httpd.conf
#sed -i '/LoadModule alias_module modules\/mod_alias.so/aLoadModule cgi_module modules/mod_cgi.so' $APACHE_CONFIG_DIR/conf/httpd.conf

cat << EOF > $GITWEB_CONF
\$projectroot = '$SERVER_DIR';
\$feature{'blame'}{'default'} = [1];
\$feature{'highlight'}{'default'} = [1];
EOF

mv $NGINX_CONF $NGINX_CONF.original

cat << EOF > $NGINX_CONF
#https://stackoverflow.com/questions/6414227/how-to-serve-git-through-http-via-nginx-with-user-password
#server {
#    listen 80;
#    server_name _;
#    return 301 https://$host$request_uri;
#}

server {
    listen       80;#443 ssl; # Replace 443 ssl by 80 if you don't want TLS
    server_name  _;
    root         /usr/share/gitweb; # Remove if you don't want Gitweb

    error_log  /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;

    # Remove ssl_* lines if you don't want TLS
    #ssl_certificate /etc/letsencrypt/live/git.example.com/fullchain.pem;
    #ssl_certificate_key /etc/letsencrypt/live/git.example.com/privkey.pem;
    #ssl_protocols             TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    #ssl_prefer_server_ciphers on;
    #ssl_ciphers               'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';

    # static repo files for cloning over http
    location ~ ^.*\.git/objects/([0-9a-f]+/[0-9a-f]+|pack/pack-[0-9a-f]+.(pack|idx))$ {
        auth_basic "Resticted Git";
        auth_basic_user_file /home/$USER/.htpasswd;
        root $SERVER_DIR;
    }

    # requests that need to go to git-http-backend
    location ~ ^.*\.git/(HEAD|info/refs|objects/info/.*|git-(upload|receive)-pack)$ {
        auth_basic "Resticted Git";
        auth_basic_user_file /home/$USER/.htpasswd;
        root $SERVER_DIR;

        fastcgi_pass  unix:/var/run/fcgiwrap/fcgiwrap.sock;
        fastcgi_param SCRIPT_FILENAME   /usr/libexec/git-core/git-http-backend;
        fastcgi_param PATH_INFO         \$uri;
        fastcgi_param GIT_PROJECT_ROOT  \$document_root;
        fastcgi_param GIT_HTTP_EXPORT_ALL "";
        fastcgi_param REMOTE_USER \$remote_user;
        include fastcgi_params;
    }

    # Remove all conf beyond if you don't want Gitweb
    try_files \$uri @gitweb;
    location @gitweb {
        #auth_basic "Resticted Git";
        #auth_basic_user_file /home/$USER/.htpasswd;

        fastcgi_pass  unix:/var/run/fcgiwrap/fcgiwrap.sock;
        fastcgi_param SCRIPT_FILENAME   /usr/share/gitweb/gitweb.cgi;
        fastcgi_param PATH_INFO         \$uri;
        fastcgi_param GITWEB_CONFIG     $GITWEB_CONF;
        include fastcgi_params;
    }
}
EOF

sed -i "s/user  nginx;/user $USER www-data;/" /etc/nginx/nginx.conf
chown -R $USER:www-data /usr/share/gitweb

# Start sshd
mv $SSHD_CONF $SSHD_CONF.original
cat << EOF > $SSHD_CONF
#	$OpenBSD: sshd_config,v 1.104 2021/07/02 05:11:21 dtucker Exp $

# This is the sshd server system-wide configuration file.  See
# sshd_config(5) for more information.

# This sshd was compiled with PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PubkeyAuthentication yes

# The default is to check both .ssh/authorized_keys and .ssh/authorized_keys2
# but this is overridden so installations will only check .ssh/authorized_keys
AuthorizedKeysFile	.ssh/authorized_keys
PasswordAuthentication no
AllowTcpForwarding no
GatewayPorts no
X11Forwarding no
UseDNS no
ChrootDirectory $SERVER_ROOT
EOF

ssh-keygen -A
/usr/sbin/sshd -f /etc/ssh/sshd_config
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start sshd: $status"
  exit $status
fi

# Start fcgiwrap
/usr/bin/spawn-fcgi -s /var/run/fcgiwrap/fcgiwrap.sock -u $USER -g www-data /usr/bin/fcgiwrap
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start fcgiwrap: $status"
  exit $status
fi

# Start nginx
/usr/sbin/nginx
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start nginx: $status"
  exit $status
fi

# Naive check runs checks once a minute to see if either of the processes exited.
# This illustrates part of the heavy lifting you need to do if you want to run
# more than one service in a container. The container exits with an error
# if it detects that either of the processes has exited.
# Otherwise it loops forever, waking up every sync interval
while true; do
  ps aux |grep sshd |grep -q -v grep
  SSHD_STATUS=$?
  ps aux |grep fcgiwrap |grep -q -v grep
  FGCIWRAP_STATUS=$?
  ps aux |grep nginx |grep -q -v grep
  NGINX_STATUS=$?
  # If the greps above find anything, they exit with 0 status
  # If they are not both 0, then something is wrong
  if [ $SSHD_STATUS -ne 0 -o $FGCIWRAP_STATUS -ne 0 -o $NGINX_STATUS -ne 0 ]; then
    echo "One of the processes has already exited."
    exit 1
  fi

  if [ -n "${ZEROTIER_ID}" ]; then
    # Check if zerotier is running, otherwise connect
    if zerotier-cli info; then
      if zerotier-cli listnetworks | grep $ZEROTIER_ID; then
          echo "Still connected to $ZEROTIER_ID all good"
      else
          zerotier-cli join $ZEROTIER_ID
      fi
    else
      zerotier-one -d
      sleep 10
      zerotier-cli join $ZEROTIER_ID
    fi
  fi

  # Running the script for syncing or backup the repos
  $SYNC_SCRIPT

  sleep ${SYNC_INTERVAL_S}
done
