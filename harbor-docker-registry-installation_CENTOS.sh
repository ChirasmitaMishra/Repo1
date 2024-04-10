#!/bin/bash

# Disable SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config

# Stop and disable firewall
systemctl stop firewalld
systemctl disable firewalld

# Set hostname
hostnamectl set-hostname harbor1

# Dynamically get the primary IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Update /etc/hosts
# Remove existing harbor1 entry to avoid duplicates
sed -i '/harbor1/d' /etc/hosts
# Add new entry
echo "$IP_ADDRESS   harbor1" >> /etc/hosts

sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

sudo yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl start docker
sudo systemctl enable docker
# Download the latest Harbor tar file
curl -s https://api.github.com/repos/goharbor/harbor/releases/latest | grep browser_download_url | cut -d '"' -f 4 | grep '\.tgz$' | wget -i -

# Unzip tar file
tarball=$(ls harbor-offline-installer-*.tgz)
tar -zxvf $tarball
directory=${tarball%.tgz}

# Navigate to the Harbor directory
cd harbor

# Configure harbor.yml
cp harbor.yml.tmpl harbor.yml
sed -i "s/hostname: reg.mydomain.com/hostname: harbor1/" harbor.yml
sed -i "s|certificate: /your/certificate/path|certificate: /root/harbor/harbor.crt|" harbor.yml
sed -i "s|private_key: /your/private/key/path|private_key: /root/harbor/harbor.key|" harbor.yml

# Generate OpenSSL config file for generating SSL certificate
cat > /etc/pki/tls/certs/harbor_certs.cnf <<EOF
[ req ]
default_bits        = 4096
prompt              = no
default_md          = sha512
distinguished_name  = dn
req_extensions      = req_ext

[ dn ]
C                   = IN
ST                  = State
L                   = Locality
O                   = Organization
OU                  = Organizational Unit
CN                  = harbor1

[ req_ext ]
subjectAltName      = @alt_names

[ alt_names ]
DNS.1               = harbor1
IP.1                = $IP_ADDRESS
EOF

# Generate SSL certificate
openssl req -newkey rsa:4096 -nodes -x509 -days 365 -keyout harbor.key -out harbor.crt -config /etc/pki/tls/certs/harbor_certs.cnf -extensions req_ext

# Setup Docker certificate directory and copy certificates
mkdir -p /etc/docker/certs.d/$IP_ADDRESS/
cp harbor.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust
cp harbor.crt /etc/docker/certs.d/$IP_ADDRESS/
cp harbor.crt /etc/docker/certs.d/$IP_ADDRESS/ca.crt

# Restart Docker to apply changes
systemctl restart docker

# Prepare and install Harbor
./prepare
./install.sh

# Check Docker containers and validate setup
docker ps
cat /etc/hosts

# Docker login test (this is just a prompt for manual action)
echo "Attempt to login to Harbor using 'docker login $IP_ADDRESS'. You might need to trust the self-signed certificate on your Docker client machine."


