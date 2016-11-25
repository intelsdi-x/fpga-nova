#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Simple config builder and cloner for VirtualBox virtual machines.

See README.rst for more details.
"""
import argparse
import errno
import os
import shutil
import subprocess
import sys
import re

import yaml


PATH = os.path.join(os.path.dirname(__file__), "modules")

class Build(object):
    """Build the configuration scripts and optionally copy it to cloned VMs"""
    VM_RE = re.compile(r'^"(?P<name>.+)"\s.*')

    def __init__(self, args, config):
        self._clone = not args.dont_clone
        self._remove_vms = args.remove
        self._skip_hosts = args.skip_hosts
        self.config = config['config']
        self.context = {'controller': [], 'compute': []}
        self.hosts = config['nodes']

        for hostname, data in self.hosts.items():
            self.context[data['role']].append(hostname)

    def build(self):
        """Build conf/clone vm"""
        self.create_configs()
        self.create_cleanup()
        if self._clone:
            self.clone_vms()

    def _check_vms_existence(self, command="vms"):
        """Return list of existing machines, that match hosts in self.hosts"""

        result = []

        try:
            out = subprocess.check_output(['VBoxManage', 'list', command])
        except subprocess.CalledProcessError:
            return result

        for item in out.split('\n'):
            match = Build.VM_RE.match(item)
            if match and match.groups()[0] in self.hosts:
                result.append(match.groupdict()['name'])

        return result

    def _remove_vm(self, host):
        """Remove virtual machine"""
        print("removing vm `%s'" % host)
        subprocess.check_call(['VBoxManage', 'unregistervm', host])
        subprocess.check_call(['rm', '-fr',
                               os.path.join(os.path.expanduser('~/'),
                                            '.config', 'VirtualBox', host)])

    def _poweroff_vm(self, host):
        """Turn off virtual machine"""
        print("power off vm `%s'" % host)
        subprocess.check_call(['VBoxManage', 'controlvm', host, 'poweroff'])

    def remove_vms(self):
        """Remove vms"""
        hosts = self._check_vms_existence()

        if hosts and not self._remove_vms:
            print ("ERROR: there is at least one VM which exists. Remove "
                   "it manually, or use --remove switch for wiping out all "
                   "existing machines before cloning.")
            print("\nConflicting VMs:")
            for host in sorted(hosts):
                print("- %s" % host)
            return False

        running_hosts = self._check_vms_existence('runningvms')

        for host in hosts:
            if host in running_hosts:
                self._poweroff_vm(host)
            self._remove_vm(host)

        return True

    def remap(self, line, data):
        """Replace the template placeholders to something meaningful"""
        line = line.rstrip()
        if 'CONTROLLER_HOSTNAME' in line:
            line = line.replace('CONTROLLER_HOSTNAME',
                                self.context['controller'][0])
        if 'AAA.BBB.CCC.DDD' in line:
            line = line.replace('AAA.BBB.CCC.DDD', data['ips'][0])
        for key, val in self.config.items():
            if key in line:
                line = line.replace(key, str(val))

        return line

    def create_cleanup(self):
        """Create cleanup conf"""

        for hostname, data in self.hosts.items():
            modules_out = hostname + "_modules"

            output = ["#!/bin/bash", ""]

            for module in reversed(data['modules']):
                mod = []
                modpath = os.path.join(modules_out, "out_" + module)
                with open(os.path.join(PATH, "out_" + module)) as fobj:
                    for line in fobj:
                        mod.append(self.remap(line, data))
                mod.append("")

                with open(modpath, "w") as fobj:
                    fobj.write('\n'.join(mod))

                output.append("bash " + modpath)
            output.append("")

            with open(hostname + "_cleanup.sh", "w") as fobj:
                fobj.write("\n".join(output))

    def clone_vms(self):
        """Cloning VMs"""
        if not self.remove_vms():
            return

        for hostname, data in self.hosts.items():
            try:
                subprocess.check_call(['./create_ubuntu_vm_clone.sh',
                                       hostname,
                                       data['ips'][0].split(".")[-1]])
            except subprocess.CalledProcessError as err:
                sys.exit(err.returncode)

    def create_configs(self):
        """Create configurations, and optionally clone and provision VMs"""

        if self._skip_hosts:
            print('Warning: You have to add appropriate entries to your '
                  '/etc/hosts, otherwise your cloud may not work properly.')

        for hostname, data in self.hosts.items():
            modules_out = hostname + "_modules"

            try:
                os.mkdir(modules_out)
            except OSError as err:
                if err.errno == errno.EEXIST:
                    shutil.rmtree(modules_out)
                    os.mkdir(modules_out)
                else:
                    raise

            output = ["#!/bin/bash", ""]

            if not self._skip_hosts:
                for other_host_key in [x
                                       for x in self.hosts
                                       if x != hostname]:

                    output.append("echo " +
                                  self.hosts[other_host_key]['ips'][0] + " " +
                                  other_host_key +
                                  " >> /etc/hosts")
                output.append("")

            for module in data['modules']:
                mod = []
                modpath = os.path.join(modules_out, "in_" + module)
                with open(os.path.join(PATH, "in_" + module)) as fobj:
                    for line in fobj:
                        mod.append(self.remap(line, data))
                mod.append("")
                with open(modpath, "w") as fobj:
                    fobj.write('\n'.join(mod))

                output.append("bash " + modpath)
            output.append("")

            with open(hostname + ".sh", "w") as fobj:
                fobj.write("\n".join(output))


def main():
    """Main function, just parses arguments, and call create_configs"""
    parser = argparse.ArgumentParser()
    parser.add_argument('--dont-clone', '-d', action='store_true',
                        help='Do not clone machine, just generate install '
                        'scripts')
    parser.add_argument('--skip-hosts', '-s', action='store_true',
                        help='Skip appending hosts to /etc/hosts')
    parser.add_argument('--remove', '-r', action='store_true',
                        help='Dispose existing VMs')
    parser.add_argument('cloudconf',
                        help='Yaml file with the cloud configuration')
    parsed_args = parser.parse_args()

    with open(parsed_args.cloudconf) as fobj:
        conf = yaml.load(fobj)

    Build(parsed_args, conf).build()


if __name__ == "__main__":
    main()
