#/bin/sh
# ChromeOS clipboard functions
#
# -   Use OSC 52 escape sequence
# -   Based upon https://github.com/chromium/hterm/blob/master/etc/osc52.vim
# -   \e and \033 and \x1b are all equivalent
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
		printf '\e]52;c;%s\a' $(printf "$1" | base64)
	else
		printf '\e]52;c;%s\a' \
			"$(tee /dev/stderr | base64 | tr -d '\n')"
	fi
	printf '\a'
}

yy() {
	# Copy the last command to the ChromeOS clipboard
	history |
	sed -n '$!h;$g;s,^ \+[0-9]\+ \+,,;$p' |
	osc52
}
