#!/bin/sh
SCRIPT='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'v0.6.0/alpine-chroot-install#a827a4ba3d0817e7c88bae17fe34e50204983d1e'
MIRROR="https://uk.alpinelinux.org/alpine/"
BUSYBOX="${MIRROR}v3.7/main/x86_64/busybox-static-1.27.2-r6.apk" #No SHA1 found

ac_get_busybox() {
	if test ! -f busybox.static ; then
		curl --silent "$BUSYBOX" |
		tar --warning=no-unknown-keyword --strip-components=1 \
			-xz bin/busybox.static
	fi
}

ac_get_aci() {
	if test ! -f alpine-chroot-install ; then
		curl --silent -O "${SCRIPT%#*}" &&
		echo "${SCRIPT#*#}  alpine-chroot-install" | sha1sum -c ||
		exit 1
	fi
	if test ! -x alpine-chroot-install ; then
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
	sudo -- sh -c "printf 'chronos:x:1000:\n' >> chroot/etc/group" &&
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
	cd $(dirname "${0}") &&
	ac_get_aci &&
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
	-p openssl
	-p python3
	-p git-perl # for git add -p
	-p git-doc # for git help
	-p man # for git help
	-p man-pages # for git help
	-p mdocml-apropos # for git help
	-p openssh # for git push
	-p util-linux # for man
	-p util-linux-doc # for man
	-p sudo # required for elevation
	-p moreutils # for vidir in edge/testing
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
	ac_get_exec_stateful_partition &&
	ac_get_suid_stateful_partition &&
	cd $(dirname "${0}") &&
	test -d chroot ||
	{ printf "Not setup: run \`${0} install\` first \n" ; exit 1 ; } &&
	if test ! -f chroot/etc/resolv.conf ; then
		sudo touch chroot/etc/resolv.conf
	fi &&
	sudo ./busybox.static unshare -m --propagation=slave \
		"$(pwd)/$(basename $0)" inside
	;;
esac
