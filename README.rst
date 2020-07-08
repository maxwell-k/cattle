======
Cattle
======

A simple script to setup a basic Alpine Linux, Debian or Ubuntu environment on
a `Chromebook` or Ubuntu Linux host. Uses a `chroot` and mount namespaces.
Includes:

- ``vim``
- ``git``
- ``openssh`` client utilities
- ``sudo``
- ``ansible``
- ``curl``

The script follows the `official instructions`_ for installing Ansible on
Ubuntu and Debian.

To install a release version of Alpine Linux without any packages use:

.. code:: sh

  BRANCH=v3.9/main ALPINE_PACKAGES="" ./enter.sh alpine_linux

.. _official instructions: https://docs.ansible.com/ansible/latest/
   installation_guide/intro_installation.html#latest-releases-via-apt-debian

Usage
-----

Chrome OS
=========

`chroots` installed by this script rely on symbolic links. Chrome OS restricts
symbolic link traversal. An exception that applies to
``/mnt/stateful_parition/dev_image`` is created when developer mode is enabled.

.. _restricts: https://www.chromium.org/chromium-os/chromiumos-design-docs/
    hardening-against-malicious-stateful-data#TOC-Restricting-symlink-traversal

The script should be installed under ``/mnt/stateful_partition/dev_image``,
replace ``cattle`` in the steps below with your choice of directory.

.. code:: sh

  cd /mnt/stateful_partition/dev_image &&
  sudo mkdir cattle &&
  cd cattle &&
  sudo chown "$LOGNAME:$LOGNAME" . &&
  curl -O https://gitlab.com/maxwell-k/cattle/raw/master/enter.sh &&
  chmod u+x enter.sh

Optionally and if using Alpine Linux create a directory to cache downloaded
files, either ``mkdir apk`` or if you prefer a directory to be shared across
chroots, first create create it, if necessary:

.. code:: sh

    cd /mnt/stateful_partition &&
    sudo mkdir apk &&
    sudo chown "$LOGNAME:$LOGNAME" apk &&
    cd -

Then link to it with ``ln -s /mnt/stateful_partition/apk``.

Review the contents of ``enter.sh`` then install [#]_ either:

1.  Alpine Linux

    .. code:: sh

        sh ./enter.sh alpine_linux

2.  Debian

    .. code:: sh

        sh ./enter.sh debian

3.  Ubuntu

    .. code:: sh

        sh ./enter.sh ubuntu

Enter the ``chroot``::

  ./enter.sh

.. [#] This command is run with ``sh`` as on boot ``/mnt/stateful_partition``
  is mounted ``noexec``, so calling directly with ``./enter.sh`` will not
  work. The script remounts the partition ``exec``.

Ubuntu and Debian
=================

This script has been tested on Ubuntu 16.04 `xenial` and 18.04 `bionic` as a
host. Usage is as above except that a few prerequisites must be
installed beforehand:

.. code:: sh

  sudo apt-get install --yes curl sudo xz-utils

For these two distributions downloading packages and installing separately is
slower and has no benefit. Slower because of a second validation pass. No
benefit because packages in `chroot/var/cache/bootstrap/` are later deleted

Background
----------

I have used a `Chromebook` as my main personal computer since buying an Acer
`C720` in 2014. Chrome OS provides an up to date browser and a pleasant
command line interface. I love that `Chromebooks` have become a ubiquitous
Linux laptop available on the high-street_; and if I break one it can easily
be replaced.

Originally I used a Gentoo Linux ``chroot``, which required a lot of time to
update. After attending a talk_ that used the cattle vs pets metaphor_, I
started this project - the aim is an easily set-up environment for my day to
day computing.

.. _high-street: https://www.argos.co.uk
.. _talk: https://www.nidevconf.com/sessions/garethfleming/
.. _metaphor: https://www.theregister.co.uk/2013/03/18/
  servers_pets_or_cattle_cern/

busybox.static
--------------

Alpine Linux includes a statically compiled version of ``busybox``. There is
no `SHA1` available for the BusyBox static ``.apk``. The Alpine Linux wiki_
has a list of available mirrors_; however only a few of these support HTTPS
for example ``nl`` and ``uk``. By default the binary is therefore downloaded
over HTTP.

BusyBox applets don't support the ``--version`` argument, so check with:

.. code:: sh

  ./busybox.static | head -n 1

.. _wiki: https://wiki.alpinelinux.org/wiki/Alpine_Linux:Mirrors
.. _mirrors: http://rsync.alpinelinux.org/alpine/MIRRORS.txt

HTTP
----

The PPA for Ubuntu and Debian uses HTTP however packages are signed.

As noted above BusyBox is downloaded over HTTP. Similarly ``cdebootstrap`` is
downloaded from the Debian UK mirror over HTTP.

Privileges
----------

Mount namespaces need ``CONFIG_USER_NS`` to be set in the kernel:

.. code:: sh

  sudo modprobe configs &&
  gunzip -c /proc/config.gz | grep CONFIG_USER_NS

Running ``./busybox.static unshare -m`` as a normal user results in::

  unshare: unshare(0x20000): Operation not permitted

``unprivileged_userns_clone`` is a Debian/Ubuntu feature and ``CAP_SYS_ADMIN``
appears not to work.

Networking
----------

*Before running any sort of process that accepts connections, you must adjust
the ``iptables`` rules.*

The default ``iptabes`` rules from a `Chromebook` are::

  $ sudo iptables -S
  -P INPUT DROP
  -P FORWARD DROP
  -P OUTPUT DROP
  -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
  -A INPUT -i lo -j ACCEPT
  -A INPUT -p icmp -j ACCEPT
  -A INPUT -d 224.0.0.251/32 -p udp -m udp --dport 5353 -j ACCEPT
  -A INPUT -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j ACCEPT
  -A FORWARD -m mark --mark 0x1 -j ACCEPT
  -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
  -A OUTPUT -m state --state NEW,RELATED,ESTABLISHED -j ACCEPT
  -A OUTPUT -o lo -j ACCEPT

Open the port for ``git`` with:

.. code:: sh

  sudo iptables -A INPUT -p tcp --dport 9418 -j ACCEPT

Close it again:

.. code:: sh

  sudo iptables -D INPUT -p tcp --dport 9418 -j ACCEPT

List and delete rules by line number:

.. code:: sh

  sudo iptables -L --line-numbers
  sudo iptables -D INPUT <number from above command>

Passwords and Ubuntu
--------------------

If `SELinux` is not in permissive mode a entering an Ubuntu ``chroot`` may
fail::

  $ sudo setenforce 1
  $ sudo getenforce
  Enforcing
  $ sh enter.sh
  Password:
  su: Authentication failure

Whereas in permissive mode this works::

  $ sudo setenforce 0
  $ sudo getenforce
  Permissive
  $ sh enter.sh
  %< --- success --- %<

A workaround is to replace ``chroot chroot/ su -l "$user"`` with ``chroot
chroot/ sudo -i -u "$user"`` in enter.sh.

.. vim: ft=rst expandtab shiftwidth=2 tabstop=2 softtabstop=2
