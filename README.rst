FPGA Integration for OpenStack* Cloud
=====================================

Aim of the FPGA Integration for OpenStack [*]_ Cloud project is to bring FPGA
accelerators as a resources available through Docker containers for the
OpenStack users.

Conventions
-----------

There are lots of shell session snippets, which have follows certain
convention.  Typical Unix/Linux environment is multiuser. To distinguish
between ordinary user and privileged ones, shell indicates that by using
different `shell prompt`_. That's why in shell snippets, the **$** in the
beginning of command line indicates non-privileged user, for example:


.. code:: shell-session
   :number-lines:

   $ whoami  # this is a comment!
   ubuntu

So the prompt in this case is ``$`` and the command was ``whoami``. Line 2 have
no sign at the beginning means output of the command - user name. Note, that
**#** sign is used for comments, which means that such thing will be ignored by
shell.

Besides **$** prompt can be also **#**, which means, that commands following it
have to be executed as ``root`` (privileged) user:

.. code:: shell-session
   :number-lines:

   $ sudo su -
   # date  # this will print current date
   Wed Aug 31 13:23:12 CEST 2016
   # whoami
   root

We have changed user to privileged one using ``su`` command (hence the **#**
prompt sign), and executed ``date`` and ``whoami`` commands as a **root** user.
Lines 3 and 4 represents output of the commands. Note, that shell sessions
in this document  have no numbered lines, so the above example would look like
this:

.. code:: shell-session

   $ sudo su -
   # date  # this will print current date
   Wed Aug 31 13:23:12 CEST 2016
   # whoami
   root

Installation of OpenStack Liberty on Ubuntu 14.04
-------------------------------------------------

Hardware requirements
+++++++++++++++++++++

For this very demo of the FPGA integration in OpenStack, there would be 3
machines needed. The minimum requirements for each of them are:

* Processor with 2+ cores
* 4GB Ram
* 10GB drive
* 2 NICs (optionally - management is all we need for the demo purposes)

One of the node should have FPGA installed, however it is not necessary for
demonstrating OpenStack part, there could be mock command used.

If needed, virtual machines might be use as well.

Software assumption:

* Only Ubuntu 14.04 is supported, with python-nova in version
  ``2:12.0.3-0ubuntu1~cloud0``
* Available command for burning/erasing/get status is required
  (`fpga-cli.py.py` is provided for getting the idea about expected
  interface)


Ubuntu Installation and configuration
+++++++++++++++++++++++++++++++++++++

The recommended installation source is the `server version of Ubuntu`_. This
demo was prepared using 14.04 LTS version. The installation is straightforward,
although it might require providing some information (like proxy servers)
depending on environment. The best way of installing the system is to keep it
minimal. For what it's worth, it might be useful to install OpenSSH server on
each node.

As for configuration options, there should be checked several things, like
below.

#. ``/etc/hostname`` - for each node provide unique host name (for example
   "controller", "compute1", "compute2")
#. ``/etc/network/interfaces`` - provide the management and public network
   configuration.
#. ``/etc/hosts`` - Idea is, that nodes should be pingable on the management
   network using their hostnames - for example:

   .. code::

       ···
       192.168.0.10 controller
       192.168.0.11 compute1
       192.168.0.12 compute2
       ···

   Following command executed on ``compute1``:

   .. code:: shell-session

      # ping controller
      PING controller (192.168.192.10) 56(84) bytes of data.
      64 bytes from controller (192.168.192.10): icmp_seq=1 ttl=64 time=0.160 ms
      64 bytes from controller (192.168.192.10): icmp_seq=2 ttl=64 time=0.221 ms
      64 bytes from controller (192.168.192.10): icmp_seq=3 ttl=64 time=0.157 ms

OpenStack installation
++++++++++++++++++++++

The main installation process is described in the `OpenStack documentation`_,
with the following assumptions:

* Services which are installed are narrowed down to:

  * Keystone
  * Nova (on controller and on computes)
  * Glance

* `nova-docker`_ [1]_ should be installed

Following components are taken as is from the installation instructions:

* `Network configuration for controller`_
* `Network configuration for compute nodes`_
* `NTP`_
* `OpenStack packages`_
* `SQL server`_
* `RabbitMQ server`_
* `Keystone`_
* `Glance`_
* `Nova`_

Docekr and nova-docker installation and configuration
+++++++++++++++++++++++++++++++++++++++++++++++++++++

Additional package `nova-docker`_ and docker itself is required on compute
nodes, along with the and following changes:

   .. code:: shell-session

      # git clone https://github.com/openstack/nova-docker -b stable/liberty
      # cd nova-docker
      # patch -Np1 -i "[/path/to/this/repository]/patches/nova_docker.patch"
      # pip install .
      # # this one is optional; useful if you want to perform simple test
      # docker pull busybox
      # docker save -o busyimg busybox

Alter the ``/etc/nova/nova.conf`` on compute nodes:

   .. code:: ini

      [DEFAULT]
      ...
      compute_driver=novadocker.virt.docker.DockerDriver

And the ``/etc/glance/glance-api.conf`` on controller node:

   .. code:: ini

      [DEFAULT]
      ...
      container_formats=ami,ari,aki,bare,ovf,ova,docker

Follow `docker installation guide`_, which basically are the following steps:

   .. code:: shell-session

      # apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 \
        --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
      # echo 'deb https://apt.dockerproject.org/repo ubuntu-trusty main' >> \
        /etc/apt/sources.list
      # apt-get update
      # apt-get purge lxc-docker
      # apt-get install docker-engine

Change the ``/etc/nova/nova-compute.conf`` to look like following on the compute
nodes:

   .. code:: ini

      [DEFAULT]
      compute_driver=novadocker.virt.docker.DockerDriver

Add users ``nova`` and ``ubuntu`` to group docker:

   .. code:: shell-session

      # usermod -a -G docker nova

Since networking is not relevant at the moment for this moment (but that's the
subject to change, obviously), installing nova-network is enough (on compute
nodes):

   .. code:: shell-session

      # apt-get install nova-network

For confidence, there are scripts for automate the process of installation under
``build_scripts`` directory.

Installation process for modifications
--------------------------------------

After having up and running OpenStack, it is time to install the modifications
and configure stack to be FPGA aware.

#. On controller alter line containing ``container_formats`` in file
   ``/etc/glance/glance-api.conf`` to looks like that:

   .. code:: ini

      container_formats = ami,ari,aki,bare,ovf,ova,docker,fpga

#. Clone `this repository`_

#. Now, patch installed nova files with provided patches:

   .. code:: shell-session

      # cd /usr/lib/python2.7/dist-packages/nova
      # nova_ver=$(dpkg -l |grep -w python-nova | sed -e "s/ii\s\+python-nova\s\+2:\([0-9.]\+\).*/\1/g")
      # echo $nova_ver
      12.0.5
      # patch -Np1 -i "[/path/to/this/repository]/patches/ubuntu_14.04-nova-${nova_ver}.patch"
      patching file compute/resource_tracker.py
      patching file db/sqlalchemy/migrate_repo/versions/303_add_fpga_field.py
      patching file db/sqlalchemy/migrate_repo/versions/304_add_fpga_instance_field.py
      patching file db/sqlalchemy/models.py
      patching file objects/block_device.py
      patching file objects/compute_node.py
      ...

#. Append following lines on ``/etc/nova.conf`` on ``[DEFAULT]`` section on
   **FPGA node**:

   .. code:: ini

      [DEFAULT]
      ...
      fpga_access = True
      fpga_simulation_mode = False

#. Alter ``/etc/nova/nova.conf`` to have the options changed or included in
   section ``[DEFAULT]`` on **controller node**:

   .. code:: ini

      [DEFAULT]
      ...
      scheduler_available_filters = nova.scheduler.filters.all_filters
      scheduler_available_filters = nova.scheduler.filters.fpga_filter.FpgaFilter
      scheduler_default_filters = RamFilter,ComputeFilter,AvailabilityZoneFilter,ImagePropertiesFilter,FpgaFilter

#. Issue necessary migration (only on controller):

   .. code:: shell-session

      # nova-manage db sync

#. Optionally, you can install ``fpga-cli.py.py`` command from ``bin`` directory
   to ``/usr/bin``, if you are installing without real FPGA hardware, or for
   some reason you don't have the real command available or you just want to
   wrap the real commands into script or executable with compatible interface.

   There is a need for modify rootwrap configuration, for enabling stub command
   to be used by compute node. Append following line for
   ``/etc/nova/rootwrap.d/compute.filters`` and
   ``/etc/nova/rootwrap.d/network.filters``:

   .. code::

      fpga-cli.py.py: CommandFilter, fpga-cli.py.py, root

   and provide configuration for it in  ``/etc/nova/nova-compute.conf`` in
   section ``[DEFAULT]``:

   .. code:: ini

      [DEFAULT]
      ...
      fpga_exec = fpga-cli.py.py

#. Create images and new flavor. First image have artificial format of *fpga*,
   and should contain zip archive (bitfiles with certain accelerator, additional
   files, and manifest file), which should be propagated to image metadata (this
   process is not done here). Second image is the system image (here: simple
   busybox image, we created earlier), which should contain all the tools
   required for accelerator use, and, what is important, it should have
   ``docker_devices`` key, which contain list of devices from ``/dev``
   filesystem, which should be passed to the container. Flavour metadata should
   point to right accelerator binaries. Below are example how match those three
   entities together for **LZO compression** accelerator.

   * FPGA `IP-Core`_ files as zip archive:

     .. code:: shell-session

        # glance image-create --id dd834aa4-f950-40e6-8c23-9dab7f3f0138 \
          --name lzo_compression --disk-format raw --container-format fpga \
          --file lzo_compression.zip
        # glance image-update \
          --property manifest='$(cat manifest.json)' \
          dd834aa4-f950-40e6-8c23-9dab7f3f0138

     where ``manifest.json`` file is the manifest file, which package
     ``lzo_compression.zip`` contains.

     Provided ``id`` is not necessary, but must be identical to the one with the
     one on flavor metadata.

   * Docker image with system and appropriate software to use accelerator:

     .. code:: shell-session

        # docker save ubuntu_lzo | glance image-create \
          --id 064704cb-b416-4acf-b149-b7272e1a9a20 --name ubuntu_lzo \
          --disk-format raw --container-format docker
        # glance image-update \
          --property docker_devices='/dev/fpga1,/dev/fpga0,/dev/fpga2' \
          064704cb-b416-4acf-b149-b7272e1a9a20

   * New flavor. Note, that passed to ``hw:fpga_ip_id`` key value is the same as
     FPGA package image created above:

     .. code:: shell-session

        # nova flavor-create fpga-lzo 6 512 1 1
        # nova flavor-key fpga-lzo set \
          "hw:fpga_ip_id"= "dd834aa4-f950-40e6-8c23-9dab7f3f0138"

     .. important::

        Instead of flavor, information passed with the ``hw:fpga_ip_id`` key
        might be passed to the proper docker image in Glance, so that it can be
        only two entities, not the three. This however might be dangerous,
        because images can be created by users, while flavors not. Such user
        created image might contain malicious IP, wich may even phisically
        destroy FPGA device.

Now restart all nova services on all nodes and you are done.
To boot newly created flavor with "fpga" image, just issue the commands:

   .. code:: shell-session

      # nova boot --flavor 6 --image ubuntu_lzo dcr1

Technical details
-----------------

Integration with the OpenStack code base have, as described in the above
instructions, assumptions:

* Support for Docker containers only, thus nova-docker have to be used
* Some kind of command line tool for programming, erasing and getting the
  status of FPGA with interface described below
* On system level accelerator programmed on FPGA should expose any kind of
  interface which might be passed to container (i.e. device from /dev
  filesystem, socket, pipe etc)

As for the OpenStack code base, nova components was changed as follows:

* ``compute/resource_tracker.py``

  - added new config option for accessing FPGA by compute host
  - added new method for updating fpga resources
  - added new ``scheduler/filters/fpga_filter.py``
  - call for ``_update_fpga_resource`` from ``_update_available_resource```

* ``db/sqlalchemy/migrate_repo`` - added two migrations for new fields in
  tables ``compute_nodes`` and ``instances``
* ``db/sqlalchemy/models.py``

  - added ``fpga_regions`` and ``fpga_regions_used`` fields for ``ComputeNode``
    model
  - added ``fpga_device`` field for ``Instance`` model

* several objects have bumped their versions due to change of ``Instance`` and
  ``ComputeNode`` classes:

  - ``BlockDeviceMapping``
  - ``BlockDeviceMappingList``
  - ``ComputeNodeList``
  - ``FixedIP``
  - ``FixedIPList``
  - ``FloatingIP``
  - ``FloatingIPList``
  - ``InstanceListv1``
  - ``SchedulerRetries``
  - ``Service``
  - ``ServiceList``

* ``scheduler/host_manager`` - ``HostState`` class was updated to make use of
  ``fpga_regions`` and ``fpga_regions_used`` fields

* unit tests where adapted to above changes

* ``fpga`` - new module that contains FPGA programming/erasing logic

* ``compute/manager`` - triggers methods from ``fpga`` module to program/erase
  FPGA

Nova-docker driver (from liberty branch), was adapted to accept list of
devices, file: ``novadocker/virt/docker/driver.py``.

For performing actual FPGA programming/erasing, the hooks facility was used to
take action before/after instance is created. There was two classes introduced:

* ``FpgaBuildInstanceHook`` which performs FGPA programming with certain IP,
  which ID can be found either on flavor *extra specs* or image *metadata*
  using command line tool.
* ``FpgaDeleteInstanceHook`` which erase FPGA.

Package containing hooks is under ``fpga_hooks`` directory and should be
installed on compute hosts, which have FPGA installed.

Cli for FPGA interaction
------------------------

There should be command line utility available, let's call it ``fpga-cli.py``,
which will be used for programming, erasing and getting status of the FPGA.

Such utility should provide following interface:

#. ``burn``. This argument require another one which is identifier of an
   `IP-Core`_ image stored in glance service. Underneath logic should be able
   to fetch such image and as a result of programming there should be returned
   an unique identifier, which will help to find and identify the right region
   for erase procedure. This could be an *uuid* or any other string, which will
   not exceed 256 characters. For example:

   .. code:: shell-session

      # fpga-cli.py burn image-id
      a0399bc1-cb67-4548-b0b8-aa95a91402d3

   In case of error, it will return non-zero value, for example:

   .. code:: shell-session

      # fpga-cli.py burn bad-image-id; echo $?
      Error: cannot programm `bad-image-id' - no matching hardware found
      64

#. ``erase``. Another argument is required, and it should be identifier
   returned by successful ``burn`` command. No output is returned, besides exit
   code, which in case of success is 0. For example:

   .. code:: shell-session

      # fpga-cli.py erase a0399bc1-cb67-4548-b0b8-aa95a91402d3; echo $?

   In case of error, it will return non-zero value, for example:

   .. code:: shell-session

      # fpga-cli.py erase bad_id; echo $?
      Error: cannot erase FPGA device with id `bad_id' - unknown region
      33

#. ``status``. Command for providing information about FPGA:

   .. code:: shell-session

      # fpga-cli.py status
      Used regions: 1/2

   Which means, that we have an FPGA have two regions, while one of it is
   occupied. Error situation will return non-zero exit code:

   .. code:: shell-session

      # fpga-cli.py status; echo $?
      Error: FPGA device is not accesible
      127

License
-------

This work is on Apache 2.0 license. See LICENSE for details.

Version
-------

Current version of this work is 0.1, and is treated as alpha/PoC stage.

.. [*] Other names and brands may be claimed as the property of others
.. [1] Until virtualization is not completed, there will be docker driver used
   as a workaround for utilizing acceleration provided by FPGA under guest.

.. _this repository: https://github.com/intelsdi-x/fpga-nova
.. _server version of Ubuntu: http://www.ubuntu.com/download/server
.. _OpenStack documentation: http://docs.openstack.org/liberty/install-guide-ubuntu/
.. _Network configuration for controller: http://docs.openstack.org/liberty/install-guide-ubuntu/environment-networking-controller.html
.. _Network configuration for compute nodes: http://docs.openstack.org/liberty/install-guide-ubuntu/environment-networking-compute.html
.. _NTP: http://docs.openstack.org/liberty/install-guide-ubuntu/environment-ntp.html
.. _OpenStack packages: http://docs.openstack.org/liberty/install-guide-ubuntu/environment-packages.html
.. _SQL server: http://docs.openstack.org/liberty/install-guide-ubuntu/environment-sql-database.html
.. _RabbitMQ server: http://docs.openstack.org/liberty/install-guide-ubuntu/environment-messaging.html
.. _Keystone: http://docs.openstack.org/liberty/install-guide-ubuntu/keystone.html
.. _Glance: http://docs.openstack.org/liberty/install-guide-ubuntu/glance.html
.. _Nova: http://docs.openstack.org/liberty/install-guide-ubuntu/nova.html
.. _nova-docker: https://github.com/openstack/nova-docker
.. _docker installation guide: https://docs.docker.com/engine/installation/linux/ubuntulinux/
.. _IP-Core: https://en.wikipedia.org/wiki/Semiconductor_intellectual_property_core
.. _shell prompt: https://en.wikipedia.org/wiki/Command-line_interface#Command_prompt
