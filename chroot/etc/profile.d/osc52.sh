#/bin/sh
# ChromeOS clipboard functions
#
# -   Use OSC 52 escape sequence
# -   Based upon https://github.com/chromium/hterm/blob/master/etc/osc52.vim
# -   \e and \033 and \x1b are all equivalent
# -   \x07 is the string terminator:
#     http://invisible-island.net/xterm/xterm.faq.html

osc52() {
	# Copy to the ChromeOS clipboard
	#
	# Usage:
	#     osc52 "argument"
	#     echo "stdin" | osc52
	#
	# relies on base64 being available e.g. via busybox
	if test -t 0 ; then
		printf "\x1b]52;c;%s\x07" $(printf "$1" | base64)
	else
		printf "\x1b]52;c;"; base64 | tr -d "\n" ; printf "\x07"
	fi
}

yy() {
	# Copy the last command to the ChromeOS clipboard
	sed -n '$!h;$g;$p' $HISTFILE |
	osc52
}
