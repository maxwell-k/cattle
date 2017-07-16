A simple script to setup a development environment on a Chromebook. Uses a
chroot and mount namespaces.

.. TODO: support separate environments
.. TODO: add notes about switching to dev mode
.. TODO: install enchant and pyenchant
.. TODO: delete env.sh and enter-chroot
.. TODO: alias
.. TODO: host name
.. TODO: man page viewer for git help
.. TODO: git username and email
.. TODO: chronos to own ~/.vimrc
.. TODO: replace less with:
    man() {
        # no version information in file path
        # fully portable
        PAGER="cat" /usr/bin/man $@ |\
        MAN_PN=1 vim -M "+runtime ftplugin/man.vim" +MANPAGER -
    }

Usage
-----

The script is designed to be installed under ``/mnt/stateful_partition``.

.. code:: sh

    cd /mnt/stateful_partition
    sudo mkdir alpine-cattle
    sudo chown chronos:chronos alpine-cattle
    cd alpine-cattle
    curl -O https://gitlab.com/keith.maxwell/alpine-cattle/raw/master/enter.sh
    # review contents of the file for security
    chmod u+x enter.sh
    sh enter.sh remount
    ./enter.sh install
    ./enter.sh

The script can also be called with an absolute path, for example::

    sh /mnt/stateful_partition/alpine-cattle/enter.sh

Background
----------

I have used a Chromebook as my main personal computer since buying an Acer C720
in 2014. Chrome OS provides an up to date browser and a pleasant command line
interface. I love that Chromebooks have become a ubiquitous Linux laptop
available on the high-street_; and if I break one it can easily be replaced.

Originally I used a Gentoo linux ``chroot``, which required a lot of time to
update. After attending a talk_ that used the cattle vs pets metaphor_, I
started this project - the aim is an easily set-up environment for my day to
day computing.

.. _high-street:
    https://www.argos.co.uk

.. _talk:
    https://www.nidevconf.com/sessions/garethfleming/

.. _metaphor:
    https://www.theregister.co.uk/2013/03/18/servers_pets_or_cattle_cern/

busybox.static
--------------

-   Alpine linux includes a static version of ``busybox``
-   The wiki_ points to a list of mirrors_, only a few suppport HTTPS including
    the ``nl`` mirror
-   As of June 2017, 3.6 is the current release_.
-   There is no SHA1 available for busybox static APK
-   Busybox applets don't support the ``--version`` argument, so check with::

    ./busybox.static | head -n 1

.. _wiki: https://wiki.alpinelinux.org/wiki/Alpine_Linux:Mirrors
.. _mirrors: http://rsync.alpinelinux.org/alpine/MIRRORS.txt
.. _release: https://wiki.alpinelinux.org/wiki/Alpine_Linux:Releases

Privileges
----------

Mount namespaces need ``CONFIG_USER_NS`` to be set in the kernel::

    sudo modprobe configs
    gunzip -c /proc/config.gz  | grep CONFIG_USER_NS

Running ``./busybox.static unshare -m`` as a normal user results in::

    unshare: unshare(0x20000): Operation not permitted

``unprivileged_userns_clone`` is a Debian/Unbuntu feature and ``CAP_SYS_ADMIN``
appears not to work.

Developing
----------

..code:: sh

    git init
    git remote add origin https://gitlab.com/keith.maxwell/alpine-cattle
    git fetch
    git reset FETCH_HEAD

.. vim: ft=rst expandtab shiftwidth=4 tabstop=4
