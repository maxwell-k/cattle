#!/bin/sh
# Script to setup Alpine Linux, Debian or Ubuntu chroots on Chrome OS
#
# All functions should call the error function on an error.
#
: "${BRANCH:=edge/main}"
: "${DEBIAN_VERSION:=buster}"
: "${MIRROR:=http://dl-cdn.alpinelinux.org/alpine}"
: "${UBUNTU_VERSION:=bionic}"
: "${ALPINE_PACKAGES=vim git openssh ansible curl}"

ar='https://busybox.net/downloads/binaries/1.30.0-i686/busybox_AR' # No checksum
busybox="$MIRROR/v3.9/main/x86_64/busybox-static-1.29.3-r10.apk" # No checksum
# packages is used on Debian and Ubuntu where the ansible package uses Python 2.7
# on Ubuntu packages must come from the main repository not universe
packages="vim,git,openssh-client,sudo,curl,python3-setuptools"
# version and sha1 is published at the top of
# https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/master/README.adoc
script='https://raw.githubusercontent.com/alpinelinux/alpine-chroot-install/'\
'v0.11.0/alpine-chroot-install'\
'#df472cbd2dc93eb0b3126d06209363c4fc328ea3'
ppa='http://ppa.launchpad.net/ansible/ansible/ubuntu'
cdebootstrap='http://ftp.uk.debian.org/debian/pool/main/c/cdebootstrap/'\
'cdebootstrap-static_0.7.7+b12_amd64.deb' # No checksum

ansible_debian() { # print commands to install Ansible on Debian
	cat <<-EOF
	apt-key adv --keyserver keyserver.ubuntu.com \
		--recv-keys 93C4A3FD7BB9C367 &&
	echo deb "$ppa" trusty main >> /etc/apt/sources.list.d/ansible.list &&
	apt-get update &&
	apt-get install --yes ansible
	EOF
}
ansible_ubuntu() { # print commands to install Ansible on Ubuntu
	# https://docs.ansible.com/ansible/latest/installation_guide/
	# intro_installation.html#latest-releases-via-apt-ubuntu
	cat <<-EOF
	add-apt-repository --yes ppa:ansible/ansible &&
	add-apt-repository --yes universe &&
	apt-get update &&
	apt-get install --yes ansible
	EOF
}
__enter() { # enter the chroot from within the mount mamespace
	test -n "$1" -a -n "$2" || error "__enter must only be used internally"
	user="$1" # at this point LOGNAME is root
	group="$2"
	for i in \
		media/removable \
		mnt/stateful_partition \
		var/srv \
		sys \
		dev \
		run \
		srv \
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
	if grep -q Ubuntu /etc/os-release && \
			grep -q Ubuntu chroot/etc/os-release ; then
		set_permissive
		if grep -q sys/fs/selinux /proc/self/mountinfo ; then
			sudo mount -o remount,ro chroot/sys/fs/selinux ||
			error "can't change selinux permissions for apt-get"
		fi
	fi
	if test -d "/home/$user/user/Downloads" ; then
		mount -o bind "/home/$user/user/Downloads" \
			"chroot/home/$user/.Downloads" ||
		error "can't bind Downloads"
	elif test -d "/home/$user/.Downloads" ; then
		mount -o bind "/home/$user/.Downloads" \
			"chroot/home/$user/.Downloads" ||
		error "can't bind Downloads"
	fi
	if test -S /var/run/docker.sock ; then
		mount -o bind /var/run/docker.sock \
			chroot/var/run/docker.sock ||
		error "can't bind docker.sock"
	fi
	if grep -q "$user" chroot/etc/passwd ; then
		exec chroot chroot/ su -l "$user"
	else
		# something went wrong, exec might terminate shell
		chroot chroot/ /bin/sh
	fi
}
error() { # display error and exit
	printf 'enter.sh: %s\n' "$1" &&
	is_interactive || exit 1
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
			-p "sudo ${ALPINE_PACKAGES}" \
			-m "$MIRROR" \
			-b "${BRANCH%/*}" \
			||
	error "Failed to run ./alpine-chroot-install"
	printf '%s\n' "$MIRROR/$BRANCH" |
	sudo tee chroot/etc/apk/repositories >> /dev/null ||
	error "Failed to limit apk repositories to just $BRANCH"
	sudo rm -f chroot/enter-chroot chroot/env.sh ||
	error "Failed to clean up after alpine-chroot-install repository"
}
is_interactive() { # check if running in a known interactive terminal
	case $0 in
	/bin/bash) true ;; # Chrome OS developer shell
	-sh|-dash) true ;; # Alpine Linux chroot
	-su) true ;; # Ubuntu chroot
	-bash) true ;; # Ubuntu EC2 instance over SSH
	*) false ;;
	esac
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
	start="$(id -nu):[^:]\\+:$(id -u)"
	if ! grep -q "^${start}:$(id -g)" chroot/etc/passwd ; then
		sudo sed -i "s/^\\(${start}\\):[^:]\\+:/\\1:$(id -g):/" \
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
	if grep debian_chroot chroot/etc/bash.bashrc >> /dev/null 2>&1 ; then
		printf "%s" "${PWD##*/}" |
		sudo -- tee chroot/etc/debian_chroot >> /dev/null ||
		error 'Failed to store chroot name'
	fi
}
prepare() { # including mount exec, download busybox and make ./tmp
	if grep -E -q '/mnt/stateful_partition .*noexec' /proc/mounts ; then
		sudo mount -o remount,exec /mnt/stateful_partition ||
		error 'cannot mount exec'
	fi
	test -d tmp || mkdir tmp || error 'cannot create tmp'
	if test ! -x busybox.static ; then
		curl --silent "$busybox" |
		tar --warning=no-unknown-keyword --strip-components=1 \
			-xz bin/busybox.static ||
		error "error getting busybox, check version ($busybox)"
	fi
}
run_cdebootstrap() {
	sudo ./cdebootstrap "${1}" chroot \
		--flavour minimal \
		--allow-unauthenticated \
		--include="${2:-${packages}}" \
		--helperdir=share/cdebootstrap-static/ \
		--configdir=share/cdebootstrap-static/
}
setup_cdebootstrap() { # make sure an executable ./cdebootsrap is available
	if test ! -x ./ar ; then
		curl --fail --location --silent --output ./ar "$ar" ||
		error 'error downloading ar'
		chmod u+x ./ar ||
		error 'error setting permissions on ar'
	fi
	if test ! -f ./cdebootstrap.deb ; then
		curl --fail --location --silent --output cdebootstrap.deb \
			"$cdebootstrap" ||
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
test_installation() { # show version numbers
	# use a mount namespace to avoid an intermittent permission denied
	# error on /dev/null on the git, ssh and ansible commands below
	sudo ./busybox.static unshare -m --propagation=slave /bin/sh <<-EOF ||
	sudo mount --bind /dev chroot/dev
	sudo chroot chroot/ vim --version | head -n 1
	sudo chroot chroot/ git --version
	sudo chroot chroot/ ssh -V
	sudo chroot chroot/ sudo --version | head -n 1
	sudo chroot chroot/ curl --version | head -n 1
	sudo chroot chroot/ python3 --version
	sudo chroot chroot/ ansible --version | head -n 1
	EOF
	error 'Failed test'
}
set_permissive() { # if appropriate change selinux permissions
	if test -x /usr/sbin/getenforce ; then
		if [ "$(sudo getenforce)" = "Enforcing" ] ; then
			sudo setenforce permissive ||
			error "can't change selinux permissions for login"
		fi
	fi
}


is_interactive || cd "$(dirname "${0}")" || error 'cannot change directory'
is_interactive || prepare
is_interactive ||
case $1 in
alpine_linux)
	install_alpine_linux
	post_install
	test_installation
	;;
debian)
	setup_cdebootstrap
	run_cdebootstrap "${DEBIAN_VERSION}" "${packages},gnupg,dirmngr" ||
	error 'cdebootstrap error extracting debian system'
	ansible_debian | sudo -- chroot chroot/ sh ||
	error 'Failed to install Ansible'
	post_install
	test_installation
	;;
ubuntu)
	setup_cdebootstrap
	set_permissive
	run_cdebootstrap "ubuntu/${UBUNTU_VERSION}" \
		"${packages},software-properties-common" ||
	error 'cdebootstrap error extracting ubuntu system'
	ansible_ubuntu | sudo -- chroot chroot/ sh ||
	error 'Failed to install Ansible'
	post_install
	test_installation
	;;
__enter) # the chroot from within the mount namespace
	__enter "$2" "$3"
	;;
*) # default if no argument
	test -d chroot || error 'run "sh enter.sh alpine_linux" first'
	if grep -E -q '/mnt/stateful_partition .*suid' /proc/mounts ; then
		sudo mount -o remount,suid /mnt/stateful_partition ||
		error 'cannot remount suid'
	fi
	exec sudo ./busybox.static unshare -m --propagation=slave \
		"$PWD/$(basename "$0")" "__enter" "$(id -nu)" "$(id -ng)"
	;;
esac

# Copyright 2018 Keith Maxwell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# enter.sh
