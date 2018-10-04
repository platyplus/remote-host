#!/bin/bash
GITHUB_REPO=platyplus/remote-host
REMOTE_SHA=`git ls-remote "https://github.com/$GITHUB_REPO" | grep HEAD | awk '{print $1}'`
LOCAL_SHA=`git ls-remote /etc/nixos | grep HEAD | awk '{print $1}'`
cd /etc/nixos
if [ ! -d /etc/nixos/.git ]; then
    git init
    git remote add origin https://github.com/platyplus/remote-host
fi
if [ "$REMOTE_SHA" != "$LOCAL_SHA" ]; then
    git fetch
    git checkout --force --track origin/master  # Force to overwrite local files
    git pull --rebase
fi