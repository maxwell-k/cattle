A simple script to setup a basic Alpine Linux, Debian or Ubuntu environment on
a `Chromebook` or Ubuntu Linux host. Uses a `chroot` and mount namespaces.
Includes:

  - ``vim``
  - ``git``
  - ``openssh`` client utilities
  - ``sudo``
  - ``ansible`` version 2.4
  - ``curl``

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
  sudo chown "$(id -nu):$(id -ng)" . &&
  curl -O https://gitlab.com/keith.maxwell/cattle/raw/master/enter.sh &&
  chmod u+x enter.sh

Optionally and if using Alpine Linux create a directory to cache downloaded
files, either ``mkdir apk`` or if you prefer a directory to be shared across
chroots, first create create it, if necessary:

.. code:: sh

    cd /mnt/stateful_partition &&
    sudo mkdir apk &&
    sudo chown "$(id -nu):$(id -ng)" apk &&
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

Then optionally run any relevant Ansible configuration.

Ubuntu
======

This script has been tested on Ubuntu 16.04 `xenial` and 18.04 `bionic` as a
host. Usage is as above except `curl` is a prerequisite which must be
installed with:

```
sudo apt-get install --yes curl sudo
```

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

- Alpine Linux includes a static version of ``busybox``
- The wiki_ points to a list of mirrors_, only a few support HTTPS including
  the ``nl`` and ``uk`` mirrors
- There is no `SHA1` available for BusyBox static ``.apk``
- BusyBox applets don't support the ``--version`` argument, so check with::

  ./busybox.static | head -n 1

.. _wiki: https://wiki.alpinelinux.org/wiki/Alpine_Linux:Mirrors
.. _mirrors: http://rsync.alpinelinux.org/alpine/MIRRORS.txt

Privileges
----------

Mount namespaces need ``CONFIG_USER_NS`` to be set in the kernel::

  sudo modprobe configs
  gunzip -c /proc/config.gz  | grep CONFIG_USER_NS

Running ``./busybox.static unshare -m`` as a normal user results in::

  unshare: unshare(0x20000): Operation not permitted

``unprivileged_userns_clone`` is a Debian/Ubuntu feature and ``CAP_SYS_ADMIN``
appears not to work.

Networking
----------

*Before running any sort of server that accepts connections, you must adjust
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

Open the port for ``git`` with::

  $ sudo iptables -A INPUT -p tcp --dport 9418 -j ACCEPT

Close it again::

  $ sudo iptables -D INPUT -p tcp --dport 9418 -j ACCEPT

List and delete rules by line number::

  $ sudo iptables -L --line-numbers
  $ sudo iptables -D INPUT <number from above command>

.. [#] This command is run with ``sh`` as on boot ``/mnt/stateful_partition``
  is mounted ``noexec``, so calling directly with ``./enter.sh`` will not
  work. The script remounts the partition ``exec``.

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

A workaround is to replace `chroot chroot/ su -l "$user"` with `chroot chroot/
sudo -i -u "$user"` in enter.sh.

.. vim: ft=rst expandtab shiftwidth=2 tabstop=2 softtabstop=2
