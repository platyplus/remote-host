#!/bin/sh
GITHUB_REPO=platyplus/remote-host
cd /etc/nixos
[ ! -d /etc/nixos/.git ]; && git init /etc/nixos &&  git remote add origin "https://github.com/$GITHUB_REPO"

git fetch
if [[ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]]; then
    git reset --hard HEAD
    git checkout --force --track origin/master  # Force to overwrite local files
    git pull --rebase
    nixos-rebuild switch --upgrade
fi
