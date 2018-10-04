#!/bin/bash
GITHUB_REPO=platyplus/remote-host
cd /etc/nixos
if [ ! -d /etc/nixos/.git ]; then
    git init
    git remote add origin "https://github.com/$GITHUB_REPO"
fi

git fetch
if [[ $(git rev-parse HEAD) != $(git rev-parse @{u}) ]]; then
    git checkout --force --track origin/master  # Force to overwrite local files
    git pull --rebase
    nixos-rebuild switch --upgrade
fi
