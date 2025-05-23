# gitweb
Minimal git server with gitweb and rsync backup in a Docker container

[![docker](https://img.shields.io/docker/cloud/build/kaitsh/gitweb)](https://hub.docker.com/repository/docker/kaitsh/gitweb)

## Getting started

Copy the env.example file and edit the variables. This config is mounted into the container.
The $REPOS variable is read during runtime.
The Backup is done via git bundle files. If a bundle exists at the backup location (with a .bundle file extension)
we copy it to the server and clone the repo. If not, we create a new repo.
After 30 seconds (the next check loop) we create a backup of the new repo.

To preserve repos and/or the zerotier config during container restarts create a volume mapping to the `/git/repos` or `/var/lib/zerotier-one` folder.

Zerotier additionally needs the ability to create tun/tap devices which can be enabled with `--cap-add=NET_ADMIN --cap-add=SYS_ADMIN --device=/dev/net/tun`
```
cp env.example env
vi env

docker run --rm -it -v $(pwd)/env:/.env:ro -p 30080:80 -p 30022:22  kaitsh/gitweb

docker run --restart=always --name gitweb -d --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --device=/dev/net/tun --add-host=host.docker.internal:host-gateway -v zerotier:/var/lib/zerotier-one -v repos:/git -v $(pwd)/env:/.env kaitsh/gitweb
```

Clone a repo with ssh or http

```
git clone ssh://git@localhost:30022/git/repo1.git

git clone http://localhost:30080/repo1.git
```

_NOTE:_ http is currently disabled. Please only use ssh.

Run the init script
```
cd repo1
./init.sh
```

## Init Script

Every new repo contains an initial commit with a `init.sh` script. This script is a setup script
for `git config` and `git hooks`. The script can be changed in `init.template`. If you want your new repositories
to be empty, remove the "initial commit" command in `sync.sh`.

By default `init.sh` configures the `git config user.name`, `git config user.email` and creates a `pre-commit`-hook and
`pre-commit.d`-hook directory. This directory contains all pre-commit hook scripts. The hook itself is a wrapper which calls all
scripts inside the hook directory. To support other hooks, simply copy the wrapper script and create a new hook directory.
By default only the `no-commit.sh` script is active. This script prevents a commit, if the changes contain a `no-commit`.

## Build a custom container

You probably only need to make changes to `service.sh` or `sync.sh`.
`service.sh` contains the config for sshd and nginx.
`sync.sh` contains config for creating and syncing the repos.

Make your changes and run

```
docker build -t local/gitweb .
```

to create a new container.

## TODOs

- [ ] HTTPS Support (must be manually enabled in `service.sh`)
- [ ] Better config
- [ ] Error handling

