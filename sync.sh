ENV="/.env"
USER=git
SERVER_ROOT=/jail
SERVER_DIR=${SERVER_ROOT}/git

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
    su "$USER" -c "rsync -IazPr ${REPO}.bundle ${BASE}.bundle"
    if [ "$?" -eq 0 ]; then
      su "$USER" -c "git clone --mirror ${BASE}.bundle $BASE"
    else
      ##########################################
      # Create empty repo without init script #
      ##########################################
      #su "$USER" -c "git init --bare ${BASE}"

      ##########################################
      # Create repo and initialize init script #
      ##########################################
      su "$USER" -c "git init ${BASE}_temp \
                    && cp /init.template ${BASE}_temp/init.sh \
                    && chmod +x ${BASE}_temp/init.sh \
                    && cd ${BASE}_temp \
                    && echo ${BASE} Repository > .git/description \
                    && git config user.name GitWeb \
                    && git config user.email gitweb@localhost \
                    && git add --all \
                    && git commit -m 'Initial commit' \
                    && cd - \
                    && git clone --mirror ${BASE}_temp $BASE \
                    && rm -rf ${BASE}_temp"
    fi
  fi
done

cd "$OLD_PATH"
