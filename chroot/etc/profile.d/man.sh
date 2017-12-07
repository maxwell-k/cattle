#/bin/sh
# Also executed from:
#   git config man.viewer
#   git config man.MANPAGER.cmd
test -f /usr/share/man/mandoc.db || sudo makewhatis
man() {
	# stderr is not affected so for example, man with no arguments will
	# result in a usage message
	if /usr/bin/man $@ > /dev/null ; then
		# portable and doesn't have version information in file paths
		PAGER="cat" /usr/bin/man $@ | MAN_PN=1 vim -M +MANPAGER -
	fi
}
test "$0" = /etc/profile.d/man.sh && man "$@"
