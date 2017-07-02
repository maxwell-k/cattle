#!/bin/sh
SCRIPT='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'v0.6.0/alpine-chroot-install#a827a4ba3d0817e7c88bae17fe34e50204983d1e'
BUSYBOX='https://nl.alpinelinux.org/alpine/v3.6/main/x86_64/'\
'busybox-static-1.26.2-r5.apk' # No SHA1 available

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
	test -f chroot/etc/profile.d/color_prompt &&
	( cd chroot/etc/profile.d/ && sudo mv color_prompt color_prompt.sh ) &&
	test -f chroot/etc/profile.d/set_vi.sh ||
	sudo -- sh -c 'printf "set -o vi\n" >> chroot/etc/profile.d/set_vi.sh'
	sudo -- sed -i '/^set nomodeline$/d' chroot/etc/vim/vimrc &&
	printf 'set noincsearch\n' |
		sudo -- sh -c 'cat - >> chroot/home/chronos/.vimrc' &&
	printf 'chronos ALL=(ALL) NOPASSWD: ALL\n' |
		sudo -- sh -c 'cat - > chroot/etc/sudoers.d/95_chronos' &&
	sudo -- sh -c "printf 'chronos:x:1000:\n' >> chroot/etc/group" &&
	true
}

case $1 in
install)
	ac_get_aci &&
	ac_get_busybox &&
	ac_get_exec_stateful_partition &&
	sed -e 's/#.*$//' <<-EOF | xargs sudo ./busybox.static \
		unshare -m --propagation=slave \
		./alpine-chroot-install \
			-d "$PWD/chroot" \
			-t "$PWD/tmp" \
			&&
	-p vim
	-p git
	-p openssl
	-p python3
	-p less # for git diff
	-p sudo # required for elevation
	-p moreutils # for vidir
	EOF
	ac_setup_profile &&
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
	chroot chroot su -l chronos
	;;
remount)
	ac_get_exec_stateful_partition
	;;
*) # default if no argument
	test -d chroot || { printf "Not setup\n" ; exit 1 ; } &&
	ac_get_exec_stateful_partition &&
	ac_get_suid_stateful_partition &&
	sudo ./busybox.static unshare -m --propagation=slave $0 inside
	;;
esac
