#!/usr/bin/env sh
USER=git
ENV=/.env
NGINX_CONF=/etc/nginx/conf.d/default.conf
GITWEB_CONF=/etc/gitweb.conf
SERVER_DIR=/git
SYNC_SCRIPT=/sync.sh

. /.env

# ---- Setup git ----
id -u $USER  &>/dev/null || adduser $USER -D
# need to make this call to enable pubkey ssh auth
passwd -d $USER
su $USER -c sh << EOC

#[ -f ~/.ssh/id_rsa ] || ssh-keygen -f ~/.ssh/id_rsa -b 2048 -t rsa -q -N ""

[ -d ~/.ssh ] || mkdir -p ~/.ssh
echo "${PRIVATE_KEY}" > ~/.ssh/id_rsa
echo "${AUTHORIZED_KEYS}" > ~/.ssh/authorized_keys
cat << EOF > ~/.ssh/config
Host *
  IdentityFile ~/.ssh/id_rsa
  StrictHostKeyChecking no
EOF

chmod 600 ~/.ssh/id_rsa
chmod 600 ~/.ssh/authorized_keys

EOC

#cat $APACHE_CONFIG_DIR/gitServer.xml >> $APACHE_CONFIG_DIR/conf/httpd.conf
#sed -i '/LoadModule alias_module modules\/mod_alias.so/aLoadModule cgi_module modules/mod_cgi.so' $APACHE_CONFIG_DIR/conf/httpd.conf

cat << EOF > /etc/gitweb.conf
\$projectroot = '$SERVER_DIR';
EOF

mv $NGINX_CONF $NGINX_CONF.original

cat << EOF > $NGINX_CONF
#https://stackoverflow.com/questions/6414227/how-to-serve-git-through-http-via-nginx-with-user-password
server {
    listen       80; # Replace 443 ssl by 80 if you don't want TLS
    server_name  _;
    root         /usr/share/gitweb; # Remove if you don't want Gitweb

    error_log  /home/git/nginx-error.log;
    access_log /home/git/nginx-access.log;

    # Remove auth_* if you don't want HTTP Basic Auth
    #auth_basic "example Git";
    #auth_basic_user_file /etc/nginx/.htpasswd;

    # static repo files for cloning over http
    location ~ ^.*\.git/objects/([0-9a-f]+/[0-9a-f]+|pack/pack-[0-9a-f]+.(pack|idx))$ {
        root $SERVER_DIR;
    }

    # requests that need to go to git-http-backend
    location ~ ^.*\.git/(HEAD|info/refs|objects/info/.*|git-(upload|receive)-pack)$ {
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
        fastcgi_pass  unix:/var/run/fcgiwrap/fcgiwrap.sock;
        fastcgi_param SCRIPT_FILENAME   /usr/share/gitweb/gitweb.cgi;
        fastcgi_param PATH_INFO         \$uri;
        fastcgi_param GITWEB_CONFIG     $GITWEB_CONF;
        include fastcgi_params;
    }
}
EOF

sed -i 's/user  nginx;/user fcgiwrap www-data;/' /etc/nginx/nginx.conf
chown -R fcgiwrap:www-data /usr/share/gitweb

# Start sshd
ssh-keygen -A
/usr/sbin/sshd -f /etc/ssh/sshd_config
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start sshd: $status"
  exit $status
fi

# Start fcgiwrap
/usr/bin/spawn-fcgi -s /var/run/fcgiwrap/fcgiwrap.sock -u fcgiwrap -g www-data /usr/bin/fcgiwrap
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
