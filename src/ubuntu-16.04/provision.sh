#!/bin/bash -e


#
# Configuration
#

unset HISTFILE
export DEBIAN_FRONTEND=noninteractive


#
# Update
#

logger --no-act -s 'Update'
apt-get update -y

logger --no-act -s 'Upgrade'
apt-get dist-upgrade -y

logger --no-act -s 'Install'
apt-get install -y \
	apt-transport-https \
	software-properties-common \
	build-essential \
	curl \
	jq \
	unzip \
	git \
	mercurial \
	subversion \
	nfs-common \
	rpcbind \
	qemu-guest-agent \
	spice-vdagent \
	xserver-xorg-video-qxl

# TODO: Install x86 libraries if x64

logger --no-act -s 'Configure MOTD'
rm -f /etc/update-motd.d/00-header
rm -f /etc/update-motd.d/10-help-text
sed -i -e 's/^\(PrintLastLog[ ]\+\).*$/\1no/' /etc/ssh/sshd_config


#
# Vagrant
#

logger --no-act -s 'Create vagrant user'
groupadd -g 1000 vagrant
useradd -g vagrant -m -s /bin/bash -u 1000 vagrant
echo vagrant:vagrant | chpasswd

logger --no-act -s 'Add sudo permissions'
cat >/etc/sudoers.d/vagrant <<'EOF'
	vagrant ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/vagrant

logger --no-act -s 'Install the Vagrant insecure public SSH key'
mkdir -p /home/vagrant/.ssh
curl -sLo /home/vagrant/.ssh/authorized_keys https://raw.githubusercontent.com/mitchellh/vagrant/master/keys/vagrant.pub
chmod -R 0600 /home/vagrant/.ssh/authorized_keys
chmod -R 0700 /home/vagrant/.ssh
chown -R vagrant:vagrant /home/vagrant/.ssh

logger --no-act -s 'Turn off DNS lookups by SSHD per Vagrant recommendation'
cat >>/etc/ssh/sshd_config <<'EOF'
	UseDNS no
EOF

logger --no-act -s 'Remove root password and restore the sshd configuration we altered during installation back to default (disable root login with password).'
usermod -p '*' root
mv /etc/default/ssh.orig /etc/default/ssh


#
# Cleanup
#

logger --no-act -s 'Reset machine ID'
rm -f /etc/machine-id
touch /etc/machine-id

logger --no-act -s 'Remove logs and caches'
apt-get -y clean
find /var/lib/apt/lists -type f -delete
systemctl stop syslog.socket
logrotate -f /etc/logrotate.conf
rm -rf \
	/var/cache/debconf/*-old \
	/var/lib/dhcp/* \
	/var/log/{*.1,apt/*,bootstrap.log,installer} \
	{/var,}/tmp/*
for file in /var/log/{faillog,lastlog,wtmp}; do >"${file}"; done

logger --no-act -s 'Zero swap partition'
export SWAP_UUID="`blkid -o value -l -s UUID -t TYPE=swap`"
swapoff /dev/vda1
dd if=/dev/zero of=/dev/vda1 bs=4096 || true
sync && sync && sync
mkswap -U "${SWAP_UUID}" /dev/vda1

logger --no-act -s 'Zero root partition'
dd if=/dev/zero of=/.zero bs=4096 || true
sync && sync && sync
rm -f /.zero

logger --no-act -s 'Expand root partition'
resize2fs -p /dev/vda2
