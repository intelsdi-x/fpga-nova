#!/bin/bash
# preparing the bare ubuntu vm cloned out of base

EXISTS=false
NAME=$1
IP=$2

if [ $# -ne 2 ]; then
   echo Usage: $0 machine-name last-ip-octet
   echo
   echo You can set env variable VMNAME to the virtual machine name which will be used
   echo 'as a clone source, otherwise "ubuntu-1404" will be used.'
   echo
   exit 1
fi

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
    src_vm="ubuntu-1404"
    [[ -n "$VMNAME" ]] && src_vm=$VMNAME
    echo "Cloning '${src_vm}' into '${NAME}'..."
    VBoxManage clonevm ${src_vm} --name ${NAME} --register
}

_boot() {
    echo "Booting '${NAME}'..."
    VBoxManage startvm ${NAME} --type headless

    while true; do
        ping -c 1 -t 1 ubuntu >/dev/null
        if [ $? -ne 0 ]; then
            echo "Still waiting for ${NAME}..."
            continue
        fi
        break
    done
    echo "Just another 5 seconds..."
    sleep 5
}

_provision() {
    echo "Provisioning '${NAME}'..."
    TMP=$(mktemp)
    echo '#!/bin/sh' > $TMP
    echo echo $NAME ' > /etc/hostname' >> $TMP
    echo "sed -i -e 's/192.168.1.2$/192.168.1.${IP}/' /etc/network/interfaces" >> $TMP
    echo "sed -i -e 's/192.168.56.2$/192.168.56.${IP}/' /etc/network/interfaces" >> $TMP
    echo "echo '192.168.1.${IP} ${NAME}' >> /etc/hosts" >> $TMP
    scp $TMP ubuntu@ubuntu:
    BTMP=$(basename $TMP)
    ssh ubuntu@ubuntu chmod +x $BTMP
    ssh ubuntu@ubuntu sudo /home/ubuntu/$BTMP
    ssh ubuntu@ubuntu rm $BTMP
    rm $TMP
    if [ -e "${NAME}.sh" ]; then
        scp "${NAME}.sh" ubuntu@ubuntu:
        ssh ubuntu@ubuntu chmod +x "${NAME}.sh"
        ssh ubuntu@ubuntu sudo mv /home/ubuntu/"${NAME}.sh" /root/
        rm "${NAME}.sh"
    fi
    if [ -e "${NAME}_cleanup.sh" ]; then
        scp "${NAME}_cleanup.sh" ubuntu@ubuntu:
        ssh ubuntu@ubuntu chmod +x "${NAME}_cleanup.sh"
        ssh ubuntu@ubuntu sudo mv /home/ubuntu/"${NAME}_cleanup.sh" /root/
        rm "${NAME}_cleanup.sh"
    fi
    if [ -e "${NAME}_modules" ]; then
        scp -r "${NAME}_modules" ubuntu@ubuntu:
        ssh ubuntu@ubuntu sudo mv /home/ubuntu/"${NAME}_modules" /root/
        rm -fr "${NAME}_modules"
    fi
}

_poweroff() {
    echo "Power off the machine"
    ssh ubuntu@ubuntu sudo poweroff

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
    ssh ubuntu@ubuntu sudo reboot
    while true; do
        ping -c 1 -t 1 ubuntu >/dev/null
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
    echo "    ssh ubuntu@${NAME}"
    echo Installation script is available on /root directory
}

_check_if_exists
_clone
_boot
_provision
_poweroff
_finalize
