Build sctipts for deploying the demo on VMs
===========================================

This directory contains helper scripts for deploying OpenStack Liberty with
FPGA integration with ease on `VirtualBox`_ or real hardware, just for
development and/or demo purposes.

Requirements
++++++++++++

Scripts were tested using VirtualBox machines, so the assumption ism that it
will be used.

* Virtualized hardware:

  * 2 CPU cores
  * 4096MB RAM
  * 3 network interfaces configured as follows:

    * 1st is NAT (with DHCP) for internet access
    * 2nd is static internal network set to ``192.168.1.2``
    * 3rd is static host only adapter set to ``192.168.56.2`` for accessing
      from host, if using VirtualBox VMs.
  * 10GB storage

* Preconfigured `Ubuntu 14.04 server`_:

  * VM name: ``ubuntu-1404``
  * Typical installation with only ssh server enabled
  * Main user: ``ubuntu``
  * Installed software (note, that most of them are for help with
    development/debugging):

    * vim
    * git
    * ipython
    * pep8
    * pylint
    * bash-completion
    * exuberant-ctags
    * htop
    * python-ipdb
    * python-pip
    * tmux
    * mc

  * Configuration

    * Sudo:

      .. code::

         %sudo   ALL=(ALL) NOPASSWD:ALL

    * Network: ``/etc/network/interfaces``:

      .. code::

         # The loopback network interface
         auto lo
         iface lo inet loopback

         # The primary network interface
         auto eth0
         iface eth0 inet dhcp

         # The primary network interface
         auto eth1
         iface eth1 inet static
         address 192.168.1.2
         netmask 255.255.255.0
         broadcast 192.168.1.255

         # The primary network interface
         auto eth2
         iface eth2 inet static
         address 192.168.56.2
         netmask 255.255.255.0
         broadcast 192.168.56.255

  * Upgrade the software:

    .. code:: shell-session

       # aptitude update && aptitude upgrade

* Host

  * SSH key exchange from host might be nice
  * The following line, should be placed in ``/etc/hosts``:

    .. code::

       192.168.56.2 ubuntu

Any other needed software may be installed in front as well.

Build the cloud
+++++++++++++++

For setting up the cloud, there would be a configuration needed. For this very
demo purpose, following yaml should be enough:

.. code:: yaml

   config: {}
   nodes:
       controller:
           ips: [192.168.56.3, 192.168.1.3]
           role: controller
           modules: [provision_conf, openstackclient_db_mq, keystone, glance,
               nova, docker, docker_glance, fpga_files, fpga_db,
               nova_scheduler_filter, flavor_and_image]
       compute1:
           ips: [192.168.56.4, 192.168.1.4]
           role: compute
           modules: [provision_conf, nova_compute, docker, nova_docker,
               fpga_files, fpga_exec]
       compute2:
           ips: [192.168.56.5, 192.168.1.5]
           role: compute
           modules: [provision_conf, nova_compute, docker, nova_docker,
               fpga_files]

Where:

* config is a dictionary with mapping for defaults for the entire cloud
  (currently they are values for the OS_* variables for OpenStack environment)
* nodes defines a machines configuration to be generated (and VM cloned), where
  the key defines the VM name and its hostname at the same time, and the items
  under it:

  * "role" is one of "compute" or "controller"
  * "ips" is list of NICs - first one is internal network, second is host only
    adapter
  * "modules" is list of configuration chunks, which will be pre-processed and
    saved as the convention of *hostname*.sh

Write the config into ``cloud.yaml``, and now it is possible for preparing the
VMs on the host:

.. code:: shell-session

   $ ./build_cloud.py cloud.yaml

This will issue the clone form ``ubuntu-1404`` to VMs which names will
correspond to the host names. Note, that script which clones machines will
refuse to clone if machine already exists.

Machines can be removed using VirtualBox GUI, ``VBoxManage`` and ``rm`` tools
or by providing an ``-r`` (``--remove``) parameter which will power off (if
needed) and removes all the virtual machines and their files, if they already
exists in yaml definition. Again, note that names of the VMs should match their
hostnames in ``/etc/hosts`` and node names in yaml cloud definition. Please be
careful with this options, since there would be no prompt for removing
confirmation.

It is also possible to just generating the installation scripts, without
cloning the VMs:

.. code:: shell-session

   $ ./build_cloud.py -d cloud.yaml

This will produce main script (and directory with modules) for each node, which
could be run on destination hosts. Scripts will be named as ``hostname.sh``, and
directory as ``hostname_modules``.

Installing OpenStack
++++++++++++++++++++

Next it is time for installing selected modules on freshly cloned images. Using
the example from above, and assuming, that ``/etc/hosts`` is filled with newly
created machines, they can be started:

.. code:: shell-session

   $ VBoxManage startvm controller --type headless
   $ VBoxManage startvm compute1 --type headless
   $ VBoxManage startvm compute2 --type headless

next connect to every node (`tmux`_ can be helpful for dividing terminal
window, and synchronizing panes to enter command in all nodes at once), and do:

.. code:: shell-session

   $ ssh ubuntu@controller
   $ sudo su -
   # ./controller.sh

for compute1 and compute2 nodes the commands are similar. After a (rather long)
while, there should be up and running setup!

.. _Ubuntu 14.04 server: http://releases.ubuntu.com/14.04/
.. _VirtualBox: https://www.virtualbox.org/
.. _tmux: https://tmux.github.io/
