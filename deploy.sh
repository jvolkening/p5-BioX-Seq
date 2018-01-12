#!/bin/bash

echo "Checking for existing build files..."
if [ -f "Build" ]
then
    ./Build distclean
fi
echo "Preparing build..."
perl Build.PL
echo "Building and deploying..."
./Build dist \
  | grep -oP 'Creating \K.+\.tar\.gz' \
  | xargs cpan-upload -u $PAUSE_USER -p $PAUSE_PASS --dry-run
