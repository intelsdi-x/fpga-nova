Build scripts for deploying the demo on VMs
===========================================

This directory contains helper scripts for deploying OpenStack with
FPGA integration with ease on `VirtualBox`_ or real hardware, just for
development and/or demo purposes.

Supported OpenStack versions and distros
++++++++++++++++++++++++++++++++++++++++
- Liberty: `Ubuntu 14.04 server`_
- Mitaka: `Ubuntu 14.04 server`_
- Newton: `Ubuntu 16.04 server`_, `RHEL 7.2`_

Requirements
++++++++++++

* VirtualBox is used to set up the cloud. ``VBoxManage`` command line tool
  should be installed.
* Virtualized hardware:

  * 2 CPU cores
  * 4096MB RAM
  * 3 network interfaces configured as follows:

    * 1st is NAT (with DHCP) for internet access
    * 2nd is static internal network set to ``192.168.1.2``
    * 3rd is static host only adapter set to ``192.168.56.2`` for accessing
      from host, if using VirtualBox VMs.
  * 15GB storage

* Preconfigured operating system:

  * Typical installation with only ssh server enabled
  * Main user: ``openstack``
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
  * RHEL operating system has to be registered with Red Hat
    Subscription Management and attached to RHEL entitlements.
  * Configuration

    * Sudo:

      .. code::

         %sudo   ALL=(ALL) NOPASSWD:ALL

    * Network:

      * First network interface: DHCP
      * Second network interface: static 192.168.1.2/24
      * Third network interface: static 192.168.56.2/24

* Host

  * SSH key exchange from host is required
  * The following line, should be placed in ``/etc/hosts``:

    .. code::

       192.168.56.2 base_openstack_vm

Any other software may be installed in front as well.

Build the cloud
+++++++++++++++

For setting up the cloud, configuration file needs to be provided. The following
yaml may be used as an example to set up Liberty on Ubuntu 14.04:

.. code:: yaml

   base_vm: ubuntu-1404
   base_user: openstack
   base_distribution: ubuntu
   base_hostname: base_openstack_vm
   openstack_version: liberty
   config: {}
   nodes:
       controller:
           ips: [192.168.56.3, 192.168.1.3]
           role: controller
           modules: [provision_conf, openstackclient_db_mq, keystone, glance,
               docker, docker_glance, nova, fpga_files, fpga_db,
               nova_scheduler_filter, flavor_and_image, horizon]
       compute1:
           ips: [192.168.56.4, 192.168.1.4]
           role: compute
           modules: [provision_conf, nova_compute, docker, nova_docker_patches,
               fpga_files, fpga_exec]
       compute2:
           ips: [192.168.56.5, 192.168.1.5]
           role: compute
           modules: [provision_conf, nova_compute, docker, nova_docker_patches,
               fpga_files]

Where:

* base_vm is a name of VirtualBox VM that will be used as a base distro
  for all OpenStack nodes
* base_user - username of the ``base_vm`` VM
* base_distribution - ``base_vm`` OS distribution. One of: ``ubuntu``,
  ``redhat``. Needs to be specified because network configuration is done
  differently depending on OS distribution
* base_hostname - host name, on which ``base_vm`` record is placed in
  ``/etc/hosts``. This host name will be used in early phase of provisioning
  cloned VM with configuration.
* openstack_version - one of: ``liberty``, ``mitaka``, ``newton`` (see
  `Supported OpenStack versions and distros`_)
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

This will issue the clone from ``base_vm`` to VMs which names will
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

Other parameters that may be passed to ``build_cloud.py``:

* ``--skip-hosts`` - do not clone machine, just generate install scripts
* ``--remove`` - dispose existing VMs
* ``--auto-install`` - automatically start VMs and run OpenStack installation
* ``--ssh-key`` - path to private SSH key used to clone git repositories
* ``-v`` - be verbose. Adding more "v" will increase verbosity
* ``-q`` - be quiet. Adding more "q" will decrease verbosity

Installing OpenStack
++++++++++++++++++++

Follow the next steps only if ``--auto-install`` parameter was not specified
in ``build_cloud.py``. Otherwise, Openstack installation on freshly cloned
images needs to be triggered. Using the above example and assuming that
``/etc/hosts`` is filled with newly created machines, they can be started
as follows:

.. code:: shell-session

   $ VBoxManage startvm controller --type headless
   $ VBoxManage startvm compute1 --type headless
   $ VBoxManage startvm compute2 --type headless

Next, connect to every node (`tmux`_ can be helpful for dividing terminal
window, and synchronizing panes to enter command in all nodes at once), and do:

.. code:: shell-session

   $ ssh <vm_user>@controller
   $ sudo su -
   # ./controller.sh

for compute1 and compute2 nodes the commands are similar. After a (rather long)
while, the setup should be up and running!

.. _Ubuntu 14.04 server: http://releases.ubuntu.com/14.04/
.. _Ubuntu 16.04 server: http://releases.ubuntu.com/16.04/
.. _RHEL 7.2: https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.2/x86_64/product-software
.. _VirtualBox: https://www.virtualbox.org/
.. _tmux: https://tmux.github.io/
