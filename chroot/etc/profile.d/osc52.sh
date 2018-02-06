#/bin/sh
# ChromeOS clipboard functions
# Should be portable to both BusyBox ash and bash
#
# -   Use OSC 52 escape sequence
# -   Based upon https://github.com/chromium/hterm/blob/master/etc/osc52.vim
# -   \e and \033 and \x1b are all equivalent
# -   dash doesn't handle \e properly, so prefer \033
# -   \x07 is the string terminator for xterm contol sequences:
#     http://invisible-island.net/xterm/xterm.faq.html
# -   \a and \x07 are equivalent

osc52() {
	# Copy to the ChromeOS clipboard
	#
	# Usage:
	#     osc52 "argument"
	#     echo "stdin" | osc52
	#
	# relies on base64 being available e.g. via busybox
	if test -t 0 ; then
		printf '\033]52;c;%s\a' $(printf "$1" | base64)
	else
		printf '\033]52;c;%s\a' \
			"$(tee /dev/stderr | base64 | tr -d '\n')"
	fi
	printf '\a'
}

yy() {
	# Copy the last command to the ChromeOS clipboard
	if [ "x$SHELL" = "x/usr/bin/dash" ] ; then
		fc -l -1 | colrm 1 6 | osc52
	elif [ "x$SHELL" = "x/bin/bash" ] ; then
		history | colrm 1 7 | tail -n 2 | head -n 1 | osc52
	else
		# BusyBox ash uses: printf("%4d %s\n", i, st->history[i]);
		# Use as catch all as per advice from Beginning Portable Shell
		# Scripting: From Novice to Professional By Peter Seebach page
		# 158
		history | colrm 1 5 | tail -n 2 | head -n 1 | osc52
	fi
}
