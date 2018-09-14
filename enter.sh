#!/bin/sh
# Script to setup Alpine Linux, Debian or Ubuntu chroots on Chrome OS
#
# All functions should exit on error.
#
# Downloading packages and installing separately is slower and has no benefit:
# - slower because of a second validation pass
# - no benefit because packages in chroot/var/cache/bootstrap/ are
#   later deleted
#
# The version number used below must be available, so check
# https://pkgs.alpinelinux.org/package/edge/main/x86_64/busybox-static
: "${BRANCH:=edge/main}"
: "${BUSYBOX_VERSION:=busybox-static-1.28.4-r2.apk}" # No SHA1
: "${MIRROR:=http://dl-cdn.alpinelinux.org/alpine}"
: "${PIP_PACKAGES:=ansible==2.6.3}" # Used on Debian and Ubuntu

busybox="$MIRROR/$BRANCH/x86_64/$BUSYBOX_VERSION"
packages="vim,git,openssh-client,sudo,curl,python3-setuptools"
script='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'v0.9.0/alpine-chroot-install#e5dfbbdc0c4b3363b99334510976c86bfa6cb251'

default() { # launch the chroot
	test -d chroot || error 'run "sh enter.sh alpine_linux" first'
	if grep -E -q '/mnt/stateful_partition .*suid' /proc/mounts ; then
		sudo mount -o remount,suid /mnt/stateful_partition ||
		error 'cannot remount suid'
	fi
	sudo ./busybox.static unshare -m --propagation=slave \
		"$(pwd)/$(basename "$0")" "enter" "$(id -nu)" "$(id -ng)"
}
enter() { # enter the chroot from within the mount namespace
	user="$1"
	group="$2"
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
	fi &&
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
}
error() { # display error and exit
	printf 'enter.sh: %s\n' "$1" &&
	exit 1
}
install_alpine_linux() { # install and configure Alpine Linux
	if test ! -f alpine-chroot-install ; then
		curl --silent -O "${script%#*}" ||
		error "downloading alpine-chroot-install failed"
		if ! echo "${script#*#} alpine-chroot-install" \
			| sha1sum -c > /dev/null
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
	bb="\\&\\& $(./busybox.static realpath ./busybox.static) " ||
	error 'issue executing busybox.static'
	bb="${bb} wget --no-check-certificate " || error 'string concatenation'
	sed -i "s,\\&\\& wget ,${bb}," alpine-chroot-install ||
	error 'failed to amend alpine-chroot-install'
	sudo ./busybox.static unshare -m --propagation=slave \
		./alpine-chroot-install \
			-d "$PWD/chroot" \
			-t "$PWD/tmp" \
			-p "vim git openssh sudo ansible curl" \
			-m "$MIRROR" \
			-b edge \
			||
	error "Failed to run ./alpine-chroot-install"
	printf '%s\n' "$MIRROR/$BRANCH" |
	sudo tee chroot/etc/apk/repositories >> /dev/null ||
	error "Failed to reset repository"
	sudo rm -f chroot/enter-chroot chroot/env.sh ||
	error "Failed to clean up after alpine-chroot-install repository"
}
install_ansible_with_pip() { # configure debian
	sudo LANG=C.UTF-8 LC_ALL=C.UTF-8 chroot chroot/ \
	python3 -m pip install "$PIP_PACKAGES" ||
	error 'error installing Ansible'
}
install_pip_on_ubuntu() { # On Ubuntu python3-pip and -wheel are in universe
	printf 'deb http://archive.ubuntu.com/ubuntu xenial universe\n' |
	sudo -- tee -a chroot/etc/apt/sources.list >> /dev/null ||
	error 'Failed to add universe to sources'
	sudo chroot chroot/ apt-get update || error 'Failed to update'
	sudo chroot chroot/ apt-get install -y \
		python3-pip \
		python3-wheel ||
	error 'Failed to install packages'
}
post_install() { # add user, group, passwordless sudo and remove vimrc
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
	# alpine-chroot-install adds the user but with gid 100 (users)
	start="$(id -nu):.:$(id -u)"
	if ! grep -q "^${start}:$(id -g)" chroot/etc/passwd ; then
		sudo sed -i "s/^${start}:[^:]\\+:/${start}:$(id -g):/" \
			chroot/etc/passwd
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
	error 'Error adding passwordless sudo'
	if test -f chroot/etc/vim/vimrc ; then
		sudo -- rm chroot/etc/vim/vimrc ||
		error 'Failed to remove vimrc'
	fi
}
prepare() { # including mount exec, cd, donwload busybox and make ./tmp
	if grep -E -q '/mnt/stateful_partition .*noexec' /proc/mounts ; then
		sudo mount -o remount,exec /mnt/stateful_partition ||
		error 'cannot mount exec'
	fi
	cd "$(dirname "${0}")" || error 'cannot change directory'
	test -d tmp || mkdir tmp || error 'cannot create tmp'
	if test ! -x busybox.static ; then
		curl --silent "$busybox" |
		tar --warning=no-unknown-keyword --strip-components=1 \
			-xz bin/busybox.static ||
		error "error getting busybox, check version ($busybox)"
	fi
}
run_cdebootstrap() { # to test: . enter.sh && cdebootstrap stretch
	sudo ./cdebootstrap "${1}" chroot \
		--flavour minimal \
		--allow-unauthenticated \
		--include="${2:-${packages}}" \
		--helperdir=share/cdebootstrap-static/ \
		--configdir=share/cdebootstrap-static/
}
setup_cdebootstrap() { # make sure an executable ./cdebootsrap is available
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
}
test_installation() {
	sudo chroot chroot/ /bin/sh <<-EOF ||
	vim --version | head -n 1
	git --version
	ssh -V
	sudo --version | head -n 1
	curl --version | head -n 1
	python3 --version
	ansible --version | head -n 1
	EOF
	error 'Failed test'
}

test "$0" = '/bin/bash' || # to load with . for debugging
case $1 in
alpine_linux)
	prepare
	install_alpine_linux
	post_install
	test_installation
	;;
debian)
	prepare
	setup_cdebootstrap
	run_cdebootstrap stretch "${packages},python3-pip,python3-wheel" ||
	error 'cdeboostrap error extracting debian system'
	install_ansible_with_pip
	post_install
	test_installation
	;;
ubuntu)
	prepare
	setup_cdebootstrap
	if grep -q ID=chromeos /etc/os-release ; then
		sudo setenforce 0 # to avoid dpkg errrors under Chrome OS
	fi
	run_cdebootstrap ubuntu/xenial "${packages},libssl-dev,libffi-dev" ||
	error 'cdeboostrap error extracting ubuntu system'
	install_pip_on_ubuntu
	install_ansible_with_pip
	post_install
	test_installation
	;;
enter) # the chroot from within the mount namespace
	enter "$2" "$3"
	;;
*) # default if no argument
	prepare
	default
	;;
esac

# Copyright 2018 Keith Maxwell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# enter.sh
