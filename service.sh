#!/usr/bin/env sh
USER=git
ENV=/.env
NGINX_CONF=/etc/nginx/conf.d/default.conf
GITWEB_CONF=/etc/gitweb.conf
SERVER_DIR=/git
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

# TODO(dgl): We get a file permission error while cloning via http. I don't know why it uses the root config
# TODO(dgl): chown did not work...
#chown -R git:www-data /root/.config/git

#cat $APACHE_CONFIG_DIR/gitServer.xml >> $APACHE_CONFIG_DIR/conf/httpd.conf
#sed -i '/LoadModule alias_module modules\/mod_alias.so/aLoadModule cgi_module modules/mod_cgi.so' $APACHE_CONFIG_DIR/conf/httpd.conf

cat << EOF > /etc/gitweb.conf
\$projectroot = '$SERVER_DIR';
$feature{'blame'}{'default'} = [1];
$feature{'highlight'}{'default'} = [1];
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

    # Remove auth_* if you don't want HTTP Basic Auth

    # static repo files for cloning over http
    location ~ ^.*\.git/objects/([0-9a-f]+/[0-9a-f]+|pack/pack-[0-9a-f]+.(pack|idx))$ {
        limit_except GET { auth_basic off; }
        auth_basic "Resticted Git";
        auth_basic_user_file /home/$USER/.htpasswd;
        root $SERVER_DIR;
    }

    # requests that need to go to git-http-backend
    location ~ ^.*\.git/(HEAD|info/refs|objects/info/.*|git-(upload|receive)-pack)$ {
        limit_except GET { auth_basic off; }
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
        limit_except GET { auth_basic off; }
        auth_basic "Resticted Git";
        auth_basic_user_file /home/$USER/.htpasswd;
        fastcgi_pass  unix:/var/run/fcgiwrap/fcgiwrap.sock;
        fastcgi_param SCRIPT_FILENAME   /usr/share/gitweb/gitweb.cgi;
        fastcgi_param PATH_INFO         \$uri;
        fastcgi_param GITWEB_CONFIG     $GITWEB_CONF;
        include fastcgi_params;
    }
}
EOF

sed -i 's/user  nginx;/user git www-data;/' /etc/nginx/nginx.conf
chown -R git:www-data /usr/share/gitweb

# Start sshd
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

# initial sync
$SYNC_SCRIPT

# Naive check runs checks once a minute to see if either of the processes exited.
# This illustrates part of the heavy lifting you need to do if you want to run
# more than one service in a container. The container exits with an error
# if it detects that either of the processes has exited.
# Otherwise it loops forever, waking up every 60 seconds
while sleep 30; do
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

  # Running the script for syncing or backup the repos
  $SYNC_SCRIPT
done
