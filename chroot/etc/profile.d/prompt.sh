#!/bin/sh
if [ "$USER" = root ]; then
	PS1="# "
else
	PS1="$ "
fi
PS1="\$? [\$(pwd | tail -c 20)]$PS1"
