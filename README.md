# gitweb
Minimal git server with gitweb and rsync backup in a Docker container

## Getting started

Copy the env.example file and edit the variables. This config is mounted into the container.
The $REPOS variable is read during runtime.
The Backup is done via git bundle files. If a bundle exists at the backup location (with a .bundle file extension)
we copy it to the server and clone the repo. If not, we create a new repo.
After 30 seconds (the next check loop) we create a backup of the new repo.

To preserve repos during container restarts create a volume mapping to the `/git` folder
```
cp env.exaple env
vi env

docker run --rm -it -v $(pwd)/env:/.env -p 30080:80 -p 30022:22  kaitsh/gitweb
```

Clone a repo with ssh or http

```
git clone ssh://git@localhost:30022/git/repo1.git

git clone http://localhost:30080/repo1.git
```

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

- [ ] HTTPS Support (must be manually enabled in `service.sh`
- [ ] Better config
