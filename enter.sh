#!/bin/sh
# Script to setup Alpine Linux Chroot on Chrome OS
#
# Based on alpine-chroot-install uses busybox.static in place of wget
SCRIPT='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'v0.9.0/alpine-chroot-install#e5dfbbdc0c4b3363b99334510976c86bfa6cb251'
MIRROR="http://dl-cdn.alpinelinux.org/alpine"
MAIN="${MIRROR}/edge/main"
# The version number used below must be available, so check
# https://pkgs.alpinelinux.org/package/edge/main/x86_64/busybox-static
BUSYBOX="${MAIN}/x86_64/busybox-static-1.28.4-r2.apk" #No SHA1 found
ALPINE_PACKAGES="vim git openssh sudo ansible curl"
DEBIAN_PACKAGES="vim,git,openssh-client,sudo,curl"
# On Debian need to install an up to date Ansible via pip:
DEBIAN_PACKAGES="${DEBIAN_PACKAGES},python-pip,libffi-dev,python-setuptools"
DEBIAN_PACKAGES="${DEBIAN_PACKAGES},python-wheel"
DEBIAN_PIP_PACKAGES="ansible==2.5"

customise() {
	# The user is added either in alpine-chroot-install or the call to
	# debian_setup
	if test -f chroot/etc/vim/vimrc ; then
		sudo -- rm chroot/etc/vim/vimrc ||
		error 'Failed to remove vimrc'
	fi
	grep ":$(id -g):" /etc/group |
	sudo -- tee -a chroot/etc/group >> /dev/null ||
	error 'Failed to add group to chroot'
	if test ! -d chroot/etc/sudoers.d ; then
		sudo -- mkdir chroot/etc/sudoers.d ||
		error 'Error creating chroot/etc/sudoers.d'
	fi
	test -f chroot/etc/sudoers.d/95_chroot ||
	printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -nu)" |
	sudo -- tee chroot/etc/sudoers.d/95_chroot >> /dev/null ||
	error 'Error adding user to wheel'
}

debian_setup() {
	if test ! -x ./ar ; then
		# Download a compiled busybox ar
		printf 'location\nfail\nsilent\nurl %s%s' \
		'https://busybox.net/downloads/binaries/1.27.1-i686/' \
		'busybox_AR' |
		curl -K - > ./ar ||
		error 'error downloading ar'
		chmod u+x ./ar ||
		error 'error setting permissions on ar'
	fi
	if test ! -f ./cdebootstrap.deb ; then
		printf 'location\nfail\nsilent\nurl %s%s%s' \
		'http://ftp.uk.debian.org/debian/' \
		'pool/main/c/cdebootstrap/' \
		'cdebootstrap-static_0.7.7+b1_amd64.deb' |
		curl -K - > cdebootstrap.deb ||
		error 'error downloading cdeboostrap'
	fi
	if test ! -x ./cdebootstrap ; then
		./ar -p cdebootstrap.deb data.tar.xz |
		tar xJ --strip-components 2 ||
		error 'error extracting cdebootstrap'
		mv ./bin/cdebootstrap-static cdebootstrap ||
		error 'error cleaning up'
		rmdir bin || error 'error cleaning up'
	fi
	if grep -E -q '/mnt/stateful_partition .*nodev' /proc/mounts ; then
		sudo mount -o remount,dev /mnt/stateful_partition ||
		error 'cannot mount dev'
	fi
	# Downloading separately is slower and has no benefit
	# - slower because of a second validation pass
	# - no benefit because packages in chroot/var/cache/bootstrap/ are
	#   later deleted
	cdebootstrap_with_args -- ||
	error 'error extracting debian system'
	sudo chroot chroot/ python2 -m pip install "$DEBIAN_PIP_PACKAGES" ||
	error 'error installing Ansible'
	if ! grep -q ":$(id -u):" chroot/etc/passwd ; then
		sudo LANG=C.UTF-8 LC_ALL=C.UTF-8 chroot chroot/ addgroup \
			--gid "$(id -g)" \
			"$(id -ng)" ||
		error 'error adding group'
		sudo LANG=C.UTF-8 LC_ALL=C.UTF-8 chroot chroot/ adduser \
			--uid "$(id -u)" \
			--gid "$(id -g)" \
			--shell /bin/bash \
			--gecos "" \
			--disabled-password \
			"$(id -nu)" ||
		error 'error adding user'
	fi
}

cdebootstrap_with_args() {
	# To test try: . enter.sh && cdebootstrap_with_args --download-only
	sudo ./cdebootstrap stretch chroot \
		--flavour minimal \
		--allow-unauthenticated \
		--include="$DEBIAN_PACKAGES" \
		--helperdir=share/cdebootstrap-static/ \
		--configdir=share/cdebootstrap-static/ \
		"$@"
	# it is difficult to pass a function to sudo, and
	# https://github.com/koalaman/shellcheck/wiki/SC2086 discourages
	# quoting
}

error() {
	printf 'enter.sh: %s\n' "$1" &&
	exit 1
}

alpine_linux_setup() {
	if test ! -f alpine-chroot-install ; then
		curl --silent -O "${SCRIPT%#*}" ||
		error "downloading alpine-chroot-install failed"
		if ! echo "${SCRIPT#*#}  alpine-chroot-install" | sha1sum -c > /dev/null
		then
			rm -f alpine-chroot-install
			error 'error getting alpine-chroot-install'
		fi
	fi
	if test -f alpine-chroot-install && test ! -x alpine-chroot-install
	then
		chmod u+x alpine-chroot-install ||
		error 'error setting permissions on alpine-chroot-install'
	fi
	bb="\\&\\& $(./busybox.static realpath ./busybox.static) wget --no-check-certificate " ||
	error 'issue executing busybox.static'
	sed -i "s,\\&\\& wget ,${bb}," alpine-chroot-install ||
	error 'failed to amend alpine-chroot-install'
	sudo ./busybox.static unshare -m --propagation=slave \
		./alpine-chroot-install \
			-d "$PWD/chroot" \
			-t "$PWD/tmp" \
			-p "$ALPINE_PACKAGES" \
			-m "$MIRROR" \
			-b edge \
			||
	error "Failed to run ./alpine-chroot-install"
	printf '%s\n' "$MAIN" |
	sudo tee chroot/etc/apk/repositories >> /dev/null ||
	error "Failed to reset repository"
	sudo rm -f chroot/enter-chroot chroot/env.sh ||
	error "Failed to clean up after alpine-chroot-install repository"
}

enter_start() {
	if grep -E -q '/mnt/stateful_partition .*noexec' /proc/mounts ; then
		sudo mount -o remount,exec /mnt/stateful_partition ||
		error 'cannot mount exec'
	fi
	cd "$(dirname "${0}")" || error 'cannot change directory'
	test -d tmp || mkdir tmp || error 'cannot create tmp'
	if test ! -x busybox.static ; then
		curl --silent "$BUSYBOX" |
		tar --warning=no-unknown-keyword --strip-components=1 \
			-xz bin/busybox.static ||
		error "error getting busybox, check version ($BUSYBOX)"
	fi
}

test "$0" = '/bin/bash' || # to load with . for debugging
case $1 in
alpine_linux)
	enter_start # exits on error
	alpine_linux_setup # exits on error
	customise # exits on error
	;;
debian)
	enter_start # exits on error
	debian_setup # exits on error
	customise # exits on error
	;;
inside) # the mount namespace
	user="$2"
	group="$3"
	for i in \
		media/removable \
		mnt/stateful_partition \
		sys \
		dev \
		run \
		; do
		if test -d "/$i" ; then
			test -d "chroot/$i" || mkdir "chroot/$i" ||
			error "cannot create $i"
			mount --rbind "/$i" "chroot/$i" ||
			error "cannot mount $i"
		fi
	done &&
	mount -t proc none chroot/proc &&
	if test -f /etc/resolv.conf ; then
		if test ! -f chroot/etc/resolv.conf ; then
			sudo touch chroot/etc/resolv.conf
		fi &&
		mount --bind /etc/resolv.conf chroot/etc/resolv.conf
	fi  &&
	if test ! -d "chroot/home/$user/.Downloads" ; then
		test -d chroot/home || mkdir chroot/home &&
		test -d "chroot/home/$user" || mkdir "chroot/home/$user" &&
		mkdir "chroot/home/$user/.Downloads" &&
		chown -R "$user:$group" "chroot/home/$user" ||
		error "Error setting up /home"
	fi &&
	if grep -q "Alpine Linux" chroot/etc/os-release && test -d apk; then
		if ! test -L chroot/etc/apk/cache ; then
			ln -s /var/cache/apk chroot/etc/apk/cache
		fi &&
		mount --bind apk chroot/var/cache/apk
	fi
	if test -d "/home/$user/user/Downloads" ; then
		mount -o bind "/home/$user/user/Downloads" \
			"chroot/home/$user/.Downloads" ||
		error "can't bind Downloads"
	fi
	if grep -q "$user" chroot/etc/passwd ; then
		chroot chroot/ su -l "$user"
	else
		chroot chroot/ /bin/sh
	fi
	;;
*) # default if no argument
	enter_start # exits if problematic
	test -d chroot || error 'run "sh enter.sh alpine_linux" first'
	if grep -E -q '/mnt/stateful_partition .*suid' /proc/mounts ; then
		sudo mount -o remount,suid /mnt/stateful_partition ||
		error 'cannot remount suid'
	fi
	sudo ./busybox.static unshare -m --propagation=slave \
		"$(pwd)/$(basename "$0")" inside "$(id -nu)" "$(id -ng)"
	;;
esac
