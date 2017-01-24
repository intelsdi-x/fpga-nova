#!/usr/bin/env bash

# Log everything to a log file named $HOSTNAME.log
exec 3>&1 1>>${HOSTNAME}.log 2>&1

_validate_input() {
    if [ -z $IP_ADDRESS ]; then
        echo "IP_ADDRESS environment variable is not set. Exiting."
        exit 1
    fi
    if [ -z $HOSTNAME ]; then
        echo "HOSTNAME environment variable is not set. Exiting."
        exit 1
    fi
    if [ -z $VMUSER ]; then
        echo "VMUSER environment variable is not set. Exiting."
        exit 1
    fi
}

_start_vm() {
    # It may happen that VM is not present on the list of 'runningvms'
    # and despite this, it cannot be started again because it is still locked
    # by a session. Just waiting a while to avoid such situation.
    sleep 10
    VBoxManage startvm $HOSTNAME --type headless
    while true; do
        ssh $VMUSER@$IP_ADDRESS hostname >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Waiting for ${HOSTNAME} to get up and running"
            sleep 2
            continue
        fi
        echo "VM ${HOSTNAME} is ready."
        break
    done
}

_run_install_script() {
    echo "Starting Openstack installation script."
    ssh $VMUSER@$IP_ADDRESS "sudo  bash /root/${HOSTNAME}.sh"
}

_validate_input
_start_vm
_run_install_script
