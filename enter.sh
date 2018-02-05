#!/bin/sh
SCRIPT='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'master/alpine-chroot-install#9049d079b136c204bfdc7f22f272e0957216a53c'
# Alternatively change the line above to point to a released version, e.g.
# 'v0.7.0/alpine-chroot-install#090d323d887ef3a2fd4e752428553f22a52b87bb'
MIRROR="https://uk.alpinelinux.org/alpine/"
# The version number used below must be available, so check
# https://pkgs.alpinelinux.org/package/v3.7/main/x86_64/busybox-static
BUSYBOX="${MIRROR}v3.7/main/x86_64/busybox-static-1.27.2-r8.apk" #No SHA1 found

error() {
	printf 'enter.sh: %s\n' "$1" &&
	exit 1
}

ac_get_busybox() {
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

ac_get_exec_stateful_partition() {
	if grep -E -q '/mnt/stateful_partition .*noexec' /proc/mounts ; then
		sudo mount -o remount,exec /mnt/stateful_partition
	fi
}

ac_get_suid_stateful_partition() {
	if grep -E -q '/mnt/stateful_partition .*suid' /proc/mounts ; then
		sudo mount -o remount,suid /mnt/stateful_partition
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

test "$0" = '/bin/bash' || # to load with . for debugging
case $1 in
install)
	cd "$(dirname "${0}")" &&
	ac_get_alpine_chroot_install &&
	ac_get_busybox &&
	ac_get_exec_stateful_partition &&
	sed -e 's/#.*$//' <<-EOF | xargs sudo ./busybox.static \
		unshare -m --propagation=slave \
		./alpine-chroot-install \
			-d "$PWD/chroot" \
			-t "$PWD/tmp" \
			-r "${MIRROR}edge/testing/" \
			&&
	-p vim
	-p git
	-p openssh # for git push
	-p sudo # required for elevation
	-p ansible # for system configuration
	EOF
	ac_setup_profile &&
	sudo rm -f chroot/enter-chroot chroot/env.sh &&
	true
	;;
inside)
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
		mount --bind /etc/resolv.conf chroot/etc/resolv.conf
	fi  &&
	if test ! -d chroot/home/chronos/.Downloads ; then
		test -d chroot/home || mkdir chroot/home &&
		test -d chroot/home/chronos || mkdir chroot/home/chronos &&
		mkdir chroot/home/chronos/.Downloads &&
		chown -R chronos:chronos chroot/home/chronos
	fi &&
	if test -d apk; then
		if ! test -L chroot/etc/apk/cache ; then
			ln -s /var/cache/apk chroot/etc/apk/cache
		fi &&
		mount --bind apk chroot/var/cache/apk
	fi  &&
	mount -o bind /home/chronos/user/Downloads \
		chroot/home/chronos/.Downloads &&
	chroot chroot su -l chronos
	;;
remount)
	ac_get_exec_stateful_partition
	;;
*) # default if no argument
	test -d chroot || error 'run "sh enter.sh install" first'
	ac_get_exec_stateful_partition &&
	ac_get_suid_stateful_partition &&
	cd "$(dirname "${0}")" &&
	if test ! -f chroot/etc/resolv.conf ; then
		sudo touch chroot/etc/resolv.conf
	fi &&
	sudo ./busybox.static unshare -m --propagation=slave \
		"$(pwd)/$(basename "$0")" inside
	;;
esac
