#!/bin/bash

REPO=$1
if [ "x$REPO" = "xiij" ]; then
	REPO="https://github.com/iij/mruby.git"
	T="iij-mruby"
else
	REPO="https://github.com/mruby/mruby.git"
	T="mruby-mruby"
fi

COUNT=100
PWD=$(pwd)
TMPDIR=$PWD/tmp/$T

if [ ! -e $PWD/tmp ]; then
	mkdir -p $PWD/tmp
fi

if [ ! -e $TMPDIR ]; then
	git clone $REPO $TMPDIR > /dev/null 2>&1
fi

cd $TMPDIR
git pull > /dev/null 2>&1
git log --oneline -n $COUNT

