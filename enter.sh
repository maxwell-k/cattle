#!/bin/sh
# Using apk-tools 2.9 in APK_TOOLS_URI and APK_TOOLS_SHA256 leads to a number
# of errors; wait for the upstream project (
# https://github.com/alpinelinux/alpine-chroot-install ) to upgrade first
SCRIPT='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'master/alpine-chroot-install#9049d079b136c204bfdc7f22f272e0957216a53c'
# Alternatively change the line above to point to a released version, e.g.
# 'v0.7.0/alpine-chroot-install#090d323d887ef3a2fd4e752428553f22a52b87bb'
MIRROR="https://uk.alpinelinux.org/alpine"
# The version number used below must be available, so check
# https://pkgs.alpinelinux.org/package/v3.7/main/x86_64/busybox-static
BUSYBOX="${MIRROR}/v3.7/main/x86_64/busybox-static-1.27.2-r8.apk" #No SHA1 found

error() {
	printf 'enter.sh: %s\n' "$1" &&
	exit 1
}

get_busybox() {
	if test ! -f busybox.static ; then
		curl --silent "$BUSYBOX" |
		tar --warning=no-unknown-keyword --strip-components=1 \
			-xz bin/busybox.static ||
		error 'error getting busybox, check version'
	fi
}

ac_get_alpine_chroot_install() {
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
		chmod u+x alpine-chroot-install
	fi
}


ac_setup_profile() {
	sudo -- rm chroot/etc/vim/vimrc &&
	sudo -- sh -c "printf 'chronos:x:1000:\\n' >> chroot/etc/group" &&
	test -d chroot/etc/sudoers.d ||
	sudo -- mkdir chroot/etc/sudoers.d &&
	test -f chroot/etc/sudoers.d/95_chronos ||
	printf 'chronos ALL=(ALL) NOPASSWD: ALL\n' |
	sudo -- tee chroot/etc/sudoers.d/95_chronos >> /dev/null &&
	true
}

enter_start() {
	cd "$(dirname "${0}")" || error 'cannot change directory'
	test -d tmp || mkdir tmp || error 'cannot create tmp'
	test -x busybox.static || get_busybox || error 'cannot get busybox'
	if grep -E -q '/mnt/stateful_partition .*noexec' /proc/mounts ; then
		sudo mount -o remount,exec /mnt/stateful_partition ||
		error 'cannot mount exec'
	fi
}

test "$0" = '/bin/bash' || # to load with . for debugging
case $1 in
install)
	enter_start # exits if problematic
	ac_get_alpine_chroot_install &&
	# openssh for git push, ansible for configuration
	sudo ./busybox.static unshare -m --propagation=slave \
		./alpine-chroot-install \
			-d "$PWD/chroot" \
			-t "$PWD/tmp" \
			-p "vim git openssh sudo ansible" \
			-m "$MIRROR" \
			-r "$MIRROR/edge/testing/" \
			&&
	ac_setup_profile &&
	sudo rm -f chroot/enter-chroot chroot/env.sh &&
	true
	;;
inside) # the mount namespace
	for i in \
		media/removable \
		mnt/stateful_partition \
		sys \
		dev \
		run \
		; do
		test -d "chroot/$i" || mkdir "chroot/$i" &&
		mount --rbind "/$i" "chroot/$i" || exit 1
	done &&
	mount -t proc none chroot/proc &&
	if test -f /etc/resolv.conf ; then
		if test ! -f chroot/etc/resolv.conf ; then
			sudo touch chroot/etc/resolv.conf
		fi &&
		mount --bind /etc/resolv.conf chroot/etc/resolv.conf
	fi  &&
	if test ! -d chroot/home/chronos/.Downloads ; then
		test -d chroot/home || mkdir chroot/home &&
		test -d chroot/home/chronos || mkdir chroot/home/chronos &&
		mkdir chroot/home/chronos/.Downloads &&
		chown -R chronos:chronos chroot/home/chronos
	fi &&
	if grep -q "Alpine Linux" chroot/etc/os-release && test -d apk; then
		if ! test -L chroot/etc/apk/cache ; then
			ln -s /var/cache/apk chroot/etc/apk/cache
		fi &&
		mount --bind apk chroot/var/cache/apk
	fi
	mount -o bind /home/chronos/user/Downloads \
		chroot/home/chronos/.Downloads || error "can't bind Downloads"
	if grep -q chronos chroot/etc/passwd ; then
		chroot chroot/ su -l chronos
	else
		chroot chroot/ /bin/sh
	fi
	;;
remount)
	ac_get_exec_stateful_partition
	;;
*) # default if no argument
	enter_start # exits if problematic
	test -d chroot || error 'run "sh enter.sh install" first'
	if grep -E -q '/mnt/stateful_partition .*suid' /proc/mounts ; then
		sudo mount -o remount,suid /mnt/stateful_partition ||
		error 'cannot remount suid'
	fi
	sudo ./busybox.static unshare -m --propagation=slave \
		"$(pwd)/$(basename "$0")" inside
	;;
esac
