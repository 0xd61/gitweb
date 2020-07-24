ENV="/.env"
USER=git
SERVER_DIR=/git

. /.env

[ -d "$SERVER_DIR" ] || mkdir -p "$SERVER_DIR"
chown -R "$USER":www-data "$SERVER_DIR"

OLD_PATH=`pwd`
cd "$SERVER_DIR"

for REPO in ${REPOS}; do
  cd "$SERVER_DIR"
  BASE=${REPO##*[:/]}
  if [ -d "$BASE" ]; then
    echo "create backup of $REPO"
    cd $BASE
    su "$USER" -c "git bundle create ../${BASE}.bundle --all && rsync -IazPr ../${BASE}.bundle ${REPO}.bundle"
  else
    echo "cloning $REPO"
    su "$USER" -c "rsync -IazPr ${REPO}.bundle ${BASE}.bundle && git clone --mirror ${BASE}.bundle $BASE || git init --bare $BASE"
  fi
done

cd "$OLD_PATH"
