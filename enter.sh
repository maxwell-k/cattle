#!/bin/sh
# Using apk-tools 2.9 in APK_TOOLS_URI and APK_TOOLS_SHA256 leads to a number
# of errors; wait for the upstream project (
# https://github.com/alpinelinux/alpine-chroot-install ) to upgrade first
SCRIPT='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'master/alpine-chroot-install#9049d079b136c204bfdc7f22f272e0957216a53c'
# Alternatively change the line above to point to a released version, e.g.
# 'v0.7.0/alpine-chroot-install#090d323d887ef3a2fd4e752428553f22a52b87bb'
MIRROR="https://uk.alpinelinux.org/alpine"
MAIN="${MIRROR}/v3.7/main"
# The version number used below must be available, so check
# https://pkgs.alpinelinux.org/package/v3.7/main/x86_64/busybox-static
BUSYBOX="${MAIN}/x86_64/busybox-static-1.27.2-r8.apk" #No SHA1 found
ALPINE_PACKAGES="vim git openssh sudo ansible curl"
DEBIAN_PACKAGES="vim,git,openssh-client,sudo,ansible,curl"

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
	error 'Error adding use to wheel'
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
		ar -p cdebootstrap.deb data.tar.xz |
		tar xJ --strip-components 2 ||
		error 'error extracting cdebootstrap'
		mv ./bin/cdebootstrap-static cdebootstrap ||
		error 'error cleaning up'
		rmdir bin || error 'error cleaning up'
	fi
	cdebootstrap_with_args --download-only ||
	error 'error downloading debian system'
	if grep -E -q '/mnt/stateful_partition .*nodev' /proc/mounts ; then
		sudo mount -o remount,dev /mnt/stateful_partition ||
		error 'cannot mount dev'
	fi
	cdebootstrap_with_args ||
	error 'error extracting debian system'
	if ! grep -q ":$(id -u):" chroot/etc/passwd ; then
		sudo chroot chroot/ \
			useradd --uid "$(id -u)" --gid users "$(id -nu)" ||
		error 'error adding user'
	fi
}

cdebootstrap_with_args() {
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
		if ! echo "${SCRIPT#*#}  alpine-chroot-install" | sha1sum -c
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
	# openssh for git push, ansible for configuration
	sudo ./busybox.static unshare -m --propagation=slave \
		./alpine-chroot-install \
			-d "$PWD/chroot" \
			-t "$PWD/tmp" \
			-p "$ALPINE_PACKAGES" \
			-m "$MIRROR" \
			-r "$MIRROR/edge/testing/" \
			||
	error "Failed to run ./alpine-chroot-install"
	printf '%s\n' "$MAIN" |
	sudo tee chroot/etc/apk/repositories >> /dev/null ||
	error "Failed to reset repository"
	sudo rm -f chroot/enter-chroot chroot/env.sh ||
	error "Failed to clean up after alpine-chroot-install repository"
}

enter_start() {
	cd "$(dirname "${0}")" || error 'cannot change directory'
	test -d tmp || mkdir tmp || error 'cannot create tmp'
	if test ! -x busybox.static ; then
		curl --silent "$BUSYBOX" |
		tar --warning=no-unknown-keyword --strip-components=1 \
			-xz bin/busybox.static ||
		error 'error getting busybox, check version'
	fi
	if grep -E -q '/mnt/stateful_partition .*noexec' /proc/mounts ; then
		sudo mount -o remount,exec /mnt/stateful_partition ||
		error 'cannot mount exec'
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
