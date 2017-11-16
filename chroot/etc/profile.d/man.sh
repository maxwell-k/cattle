#/bin/sh
# Also executed from:
#   git config man.viewer
#   git config man.MANPAGER.cmd
test -f /usr/share/man/mandoc.db || sudo makewhatis
man() {
	if /usr/bin/man $@ > /dev/null ; then
		# portable and doesn't have version information in file paths
		PAGER="cat" /usr/bin/man $@ | \
		MAN_PN=1 vim -M "+runtime ftplugin/man.vim" +MANPAGER -
	fi
}
test "$0" = /etc/profile.d/man.sh && man "$@"
