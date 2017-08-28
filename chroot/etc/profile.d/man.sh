test -f /usr/local/share/man/mandoc.db || sudo makewhatis
man() {
	# portable and doesn't have version information in file paths
	PAGER="cat" /usr/bin/man $@ | \
	MAN_PN=1 vim -M "+runtime ftplugin/man.vim" +MANPAGER -
}
