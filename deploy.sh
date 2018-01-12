#!/usr/bin/env sh

if [ -f "Build" ]
then
    ./Build distclean
fi
perl Build.PL
./Build dist \
  | grep -oP 'Creating \K.+\.tar\.gz' \
  | xargs cpan-upload -u $PAUSE_USER -p $PAUSE_PASS --dry-run
