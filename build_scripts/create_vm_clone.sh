#!/bin/bash
# preparing the bare openstack vm cloned out of base

_check_if_exists() {
    local vms=''
    vms=$(VBoxManage list vms | \
        awk -F ' {' '{ print $1 }' | \
        tr '\n' '|' | \
        sed 's/|$//' | \
        sed 's/"//g')
    IFS='|' read -ra vms <<< "$vms"

    for item in "${vms[@]}"
    do
        [[ "${item}" == "${NAME}" ]] && \
            echo "VM '${NAME}' already exists." && \
            exit 2
    done
}

_clone() {
    echo "Cloning '${VMNAME}' into '${NAME}'..."
    VBoxManage clonevm ${VMNAME} --name ${NAME} --register
}

_boot() {
    echo "Booting '${NAME}'..."
    VBoxManage startvm ${NAME} --type headless

    while true; do
        ping -c 1 -t 1 $BASE_HOSTNAME >/dev/null
        if [ $? -eq 0 ]; then
            break
        fi
        echo "Still waiting for ${NAME}..."
    done

    while true; do
        ssh $VMUSER@$BASE_HOSTNAME ls >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Still waiting for ${NAME}..."
            sleep 1
            continue
        fi
        break
    done
}

_provision() {
    echo "Provisioning '${NAME}'..."
    TMP=$(mktemp)
    echo '#!/bin/sh' > $TMP
    echo echo $NAME ' > /etc/hostname' >> $TMP

    if [ $DISTRO == 'ubuntu' ]; then
        echo "sed -i -e 's/192.168.1.2$/192.168.1.${IP}/' /etc/network/interfaces" >> $TMP
        echo "sed -i -e 's/192.168.56.2$/192.168.56.${IP}/' /etc/network/interfaces" >> $TMP
    elif [ $DISTRO == 'redhat' ]; then
        echo "sed -i -e 's/192.168.1.2$/192.168.1.${IP}/' /etc/sysconfig/network-scripts/*" >> $TMP
        echo "sed -i -e 's/192.168.56.2$/192.168.56.${IP}/' /etc/sysconfig/network-scripts/*" >> $TMP
    fi

    echo "echo '192.168.1.${IP} ${NAME}' >> /etc/hosts" >> $TMP
    scp $TMP $VMUSER@${BASE_HOSTNAME}:
    BTMP=$(basename $TMP)
    ssh $VMUSER@${BASE_HOSTNAME} chmod +x $BTMP
    ssh $VMUSER@${BASE_HOSTNAME} sudo /home/$VMUSER/$BTMP
    ssh $VMUSER@${BASE_HOSTNAME} rm $BTMP
    rm $TMP

    if [ $SSH_KEY ]; then
        scp $SSH_KEY $VMUSER@${BASE_HOSTNAME}:/home/$VMUSER/id_rsa
        ssh $VMUSER@${BASE_HOSTNAME} sudo mkdir -p /root/.ssh
        ssh $VMUSER@${BASE_HOSTNAME} sudo mv /home/$VMUSER/id_rsa /root/.ssh/id_rsa
        # This is done in order to omit the prompt when connecting to github for the first time
        ssh $VMUSER@${BASE_HOSTNAME} "sudo ssh-keyscan -t rsa github.com > known_hosts"
        ssh $VMUSER@${BASE_HOSTNAME} sudo mv known_hosts /root/.ssh/known_hosts
    fi
    if [ -e "${NAME}.sh" ]; then
        scp "${NAME}.sh" $VMUSER@${BASE_HOSTNAME}:
        ssh $VMUSER@${BASE_HOSTNAME} chmod +x "${NAME}.sh"
        ssh $VMUSER@${BASE_HOSTNAME} sudo mv /home/$VMUSER/"${NAME}.sh" /root/
        rm "${NAME}.sh"
    fi
    if [ -e "${NAME}_cleanup.sh" ]; then
        scp "${NAME}_cleanup.sh" $VMUSER@${BASE_HOSTNAME}:
        ssh $VMUSER@${BASE_HOSTNAME} chmod +x "${NAME}_cleanup.sh"
        ssh $VMUSER@${BASE_HOSTNAME} sudo mv /home/$VMUSER/"${NAME}_cleanup.sh" /root/
        rm "${NAME}_cleanup.sh"
    fi
    if [ -e "${NAME}_modules" ]; then
        scp -r "${NAME}_modules" $VMUSER@${BASE_HOSTNAME}:
        ssh $VMUSER@${BASE_HOSTNAME} sudo mv /home/$VMUSER/"${NAME}_modules" /root/
        rm -fr "${NAME}_modules"
    fi
}

_poweroff() {
    echo "Power off the machine"
    ssh $VMUSER@${BASE_HOSTNAME} sudo poweroff

    while true; do
        $(VBoxManage list runningvms |grep -q $NAME)
        if [ $? -eq 1 ]; then
            break
            sleep 1
        fi
    done
}

_reboot() {
    echo "Rebooting ${NAME}"
    ssh $VMUSER@${BASE_HOSTNAME} sudo reboot
    while true; do
        ping -c 1 -t 1 ${BASE_HOSTNAME} >/dev/null
        if [ $? -ne 0 ]; then
            echo "Still waiting for ${NAME}..."
            continue
        fi
        break
    done
    sleep 3
}

_finalize() {
    echo Done.
    echo Now you can start VM:
    echo "    VBoxManage startvm ${NAME} --type headless"
    echo and connect via ssh:
    echo "    ssh $VMUSER@${NAME}"
    echo Installation script is available on /root directory
}

_usage() {
    echo Usage: $0 machine-name last-ip-octet base-vm-name base-host-name
    echo
    echo "Also, script needs following environment variables to be set:"
    echo "- VMNAME - name of the VBox virtual machine"
    echo "- VMUSER - user, which is used to log in into the system"
    echo "- BASE_HOSTNAME - host name which points to the IP address of VMNAME"
    echo "- DISTRO - Linux distribution, one of ubuntu, redhat."
    echo "- NAME - host name which will be set on cloned machine. This will "
    echo "         also become a VBox virtual machine name."
    echo "- LAST_OCTET - last address IP octet which would be set on the cloned"
    echo "               machine"
}

_check_variables() {
    [[ -n "${VMNAME}" ]] && \
    [[ -n "${VMUSER}" ]] && \
    [[ -n "${BASE_HOSTNAME}" ]] && \
    [[ -n "${DISTRO}" ]] && \
    [[ -n "${NAME}" ]] && \
    [[ -n "${LAST_OCTET}" ]] && return || _usage && exit 1
}

EXISTS=false
IP=$LAST_OCTET

if [ $# -ne 0 ]; then
    _usage
   exit 1
fi

_check_variables
_check_if_exists
_clone
_boot
_provision
_poweroff
_finalize
