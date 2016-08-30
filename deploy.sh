#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

# Set up some git information.
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`

SOURCE_BRANCH="master"
TARGET_BRANCH="gh-pages"

function doCompile {
    make
}

# Pull requests and commits to other branches shouldn't try to deploy, just build to verify
if [ "$TRAVIS_PULL_REQUEST" != "false" -o "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]; then
    echo "Skipping deploy; just doing a build."
    doCompile
    exit 0
fi

# Clone the existing gh-pages for this repo into a temporary folder $CHECKOUT.
CHECKOUT=`mktemp -d`
git clone $REPO $CHECKOUT
git -C $CHECKOUT config user.name "Travis CI"
git -C $CHECKOUT config user.email "$COMMIT_AUTHOR_EMAIL"
# Create a new empty branch if gh-pages doesn't exist yet (should only happen on first deploy).
git -C $CHECKOUT checkout $TARGET_BRANCH || git -C $CHECKOUT checkout --orphan $TARGET_BRANCH

# Replace existing contents of checkout with the results of a fresh compile.
rm -rf $CHECKOUT/* || exit 0
doCompile
mv book/* $CHECKOUT

# If there are no changes to the compiled book (e.g. this is a README update) then just bail.
if [[ -z `git -C $CHECKOUT status --porcelain` ]]; then
    echo "No changes to the output on this push; exiting."
    exit 0
fi

# Commit the "changes", i.e. the new version. The delta will show diffs between new and old versions.
git -C $CHECKOUT commit -am "Deploy to GitHub Pages: ${SHA}"

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc.
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
openssl aes-256-cbc -K $ENCRYPTED_KEY -iv $ENCRYPTED_IV -in deploy_key.enc -out deploy_key -d
chmod 600 deploy_key
eval `ssh-agent -s`
ssh-add deploy_key

# Now that we're all set up, we can push.
git -C $CHECKOUT push $SSH_REPO $TARGET_BRANCH

# Clean up after ourselves.
rm -rf $CHECKOUT
