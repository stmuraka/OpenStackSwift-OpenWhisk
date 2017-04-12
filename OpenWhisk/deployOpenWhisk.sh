#!/usr/bin/env bash

# This script will deploy OpenWhisk on an Ubuntu 16.04 server
# You can pass in additional IP addresses to add to the SSL Cert
# e.g. ./deployOpenWhisk.sh 192.168.1.10 10.100.200.10 ...

set -euo pipefail

echo "=====================================================================#"
echo ""
echo "Installing OpenWhisk"
echo "--------------------"
echo ""

# Must run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or use sudo $0" 1>&2
   exit 1
fi
# determine real user
[[ -z "${SUDO_USER:-}" ]] || USER="${SUDO_USER}"

additional_cert_ips=()
# take run parameters as IPs to be added to SSL cert
[[ ${#} -gt 0 ]] && additional_cert_ips=( ${@} )

# Function that validates an IP address; returns 0 if valid
validate_ip () {
    local ip_address=${1}
    local valid=1
    # check if #.#.#.# format
    if [[ "${ip_address}" =~ [1-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octet <<< "${ip_address}"
        # check if [1-255].[0-255].[0-255].[0-255]
        [[ "${octet[0]}" -ge "1" && "${octet[0]}" -le "255" ]] && \
        [[ "${octet[1]}" -ge "0" && "${octet[1]}" -le "255" ]] && \
        [[ "${octet[2]}" -ge "0" && "${octet[2]}" -le "255" ]] && \
        [[ "${octet[3]}" -ge "0" && "${octet[3]}" -le "255" ]] && \
        valid=0
    fi

    # return result; a valid ip returns 0, invalid returns 1
    echo "${valid}"
}

# Get Ubuntu release
ubuntu_codename=$(lsb_release -a 2>/dev/null | grep 'Codename:' | awk '{print $2}') || { echo "ERROR: failed to get codename"; exit 1; }

# Install git and other packages
echo "Installing pre-requisite packages"
apt-get update
apt-get install -y \
        ant \
        git \
        gcc \
        jq \
        python-dev \
        python-pip \
        python-setuptools \
        software-properties-common \
        python-software-properties \
        build-essential \
        libssl-dev \
        libffi-dev
echo ""

# upgrade pip
echo "Upgrading python setup packages"
pip install pip setuptools requests[security] --upgrade
echo ""

# Download OpenWhisk code from github.com
echo "OpenWhisk will be downloaded into: ${HOME}"
cd ${HOME}/
echo ""
if [ -d ${HOME}/openwhisk ]; then
    echo "Updating openwhisk source code"
    cd ${HOME}/openwhisk
    git pull origin master
else
    echo "Downloading OpenWhisk from github.com"
    git clone https://github.com/openwhisk/openwhisk.git
fi
chown -R ${USER}:${USER} ${HOME}/openwhisk/

echo ""
cd ${HOME}/openwhisk/tools/ubuntu-setup
# tested with commit id b581cc43a87e25cd4774313718f50fabca1efecc
#git checkout b581cc43a87e25cd4774313718f50fabca1efecc

# Update release in docker script
echo -n "Patching scripts..."
sed -i -e "s/trusty/${ubuntu_codename}/g" ./docker.sh
# Update docker version
docker_version="1.12.6-0~ubuntu-${ubuntu_codename}"
sed -i -e "s/docker-engine=.*/docker-engine=${docker_version}/" ./docker.sh
[ ${ubuntu_codename} == "xenial" ] && sed -i -e "s/--force-yes/--allow-unauthenticated/" ./docker.sh
# remove force flag
sed -i -e "s/--force-yes//g" ./docker.sh
# change docker user - whoami to this user
sed -i -e "s/\`whoami\`/${USER}/g" ./docker.sh

# Update all.sh script to prevent running each script in background
sed -i -e "s/&//g" ./all.sh

# Update ansible install script for permissions on ${HOME}/.ansible dir
sed -i -e "/^ansible /i chown -R ${USER}:${USER} ~${USER}\/.ansible/" ansible.sh

#------------------------------
# Install OpenWhisk dependencies
#------------------------------
echo "Installing OpenWhisk dependencies"
./all.sh

# Add user to docker group
usermod -aG docker ${USER}

# update unit file
docker_dropin_dir="/etc/systemd/system/docker.service.d"
docker_dropin_unit="docker.conf"
mkdir -p ${docker_dropin_dir}

# check if /etc/sysconfig/docker exists
override_unit="${docker_dropin_dir}/${docker_dropin_unit}"
if [ ! -f ${override_unit} ]; then
    cp /lib/systemd/system/docker.service ${override_unit}
    sed -i -e "/ExecStart=/i EnvironmentFile=-/etc/default/docker" ${override_unit}
    sed -i -e "/ExecStart=/ s/$/ \$DOCKER_OPTS/" ${override_unit}
    sed -i -e "/ExecStart=/i ExecStart=" ${override_unit}
fi

if [[ $(which systemctl) ]]; then
    systemctl daemon-reload
    systemctl restart docker
else
    service docker restart
fi
echo ""

#------------------------------
# Build OpenWhisk
#------------------------------
echo "Building OpenWhisk"
cd ${HOME}/openwhisk
./gradlew distDocker
echo ""
chown -R ${USER}:${USER} ${HOME}/openwhisk/

#------------------------------
# configure /etc/ssl/openssl.cnf with IPs and hostname
#------------------------------
openssl_config="/etc/ssl/openssl.cnf"
echo -n "Configuring ${openssl_config} ... "
docker0ip=$(ip a show dev docker0 | grep 'inet ' | awk '{print $2}' | cut -d '/' -f1) || true
default_interface=$(ip route show | grep '^default' | awk '{ print $NF }') || { echo "ERROR: Unable to find the default interface"; exit 1; }
hostip=$(ip a show dev ${default_interface} | grep 'inet ' | awk '{print $2}' | cut -d '/' -f1) || { echo "ERROR: Unable parse the host IP address"; exit 1; }
# Add IPs from input if valid
valid_cert_ips=()
if [[ ${#additional_cert_ips[@]} -gt 0 ]]; then
    for ip in "${additional_cert_ips[@]}"; do
        # Add validated ${ip}
        [[ "$(validate_ip ${ip})" == "0" ]] && valid_cert_ips+=("${ip}")
    done
fi

# Modifty ${openssl_config}
cp ${openssl_config} ${openssl_config}.orig
# uncomment [req] req_extensions = v3_req
sed -i -e "s/^# req_extensions/req_extensions/" ${openssl_config}
# add Subject Alternative Names (SAN) to the cert request by updating openssl.conf
sed -i -e "/\[ v3_req \]/a subjectAltName = @alt_names" ${openssl_config}
sed -i -e "/\[ v3_ca \]/a subjectAltName = @alt_names" ${openssl_config}
sed -i -e "/\[ v3_ca \]/i [ alt_names ]" ${openssl_config}
sed -i -e "/\[ alt_names \]/a \ " ${openssl_config}
ip_count=2
[[ ! -z ${docker0ip} ]] && ((ip_count++))
# Add valid IPs to openssl.cnf
if [[ ${#valid_cert_ips[@]} -gt 0 ]]; then
    cert_ip_index=$((${ip_count} + ${#valid_cert_ips[@]}))
    for ip in "${valid_cert_ips[@]}"; do
        #printf 'sed -i -e "/\[ alt_names \]/a IP.%s = %s" ${openssl_config}\n' ${cert_ip_index} ${ip}
        sed -i -e "/\[ alt_names \]/a IP.${cert_ip_index} = ${ip}" ${openssl_config}
        ((cert_ip_index--))
    done
fi
[[ ! -z ${docker0ip} ]] && sed -i -e "/\[ alt_names \]/a IP.3 = ${docker0ip}" ${openssl_config}
sed -i -e "/\[ alt_names \]/a IP.2 = 127.0.0.1" ${openssl_config}
sed -i -e "/\[ alt_names \]/a IP.1 = ${hostip}" ${openssl_config}
sed -i -e "/\[ alt_names \]/a DNS.3 = localhost.localdomain" ${openssl_config}
sed -i -e "/\[ alt_names \]/a DNS.2 = localhost" ${openssl_config}
sed -i -e "/\[ alt_names \]/a DNS.1 = $(hostname)" ${openssl_config}
echo "done"
echo ""

# add request extensions to genssl script for SAN support
sed -i -e "s/^\s*-days.*/    -days 365 \\\/" ${HOME}/openwhisk/ansible/roles/nginx/files/genssl.sh
echo "    -extfile /etc/ssl/openssl.cnf \\" >> ${HOME}/openwhisk/ansible/roles/nginx/files/genssl.sh
echo "    -extensions v3_ca" >> ${HOME}/openwhisk/ansible/roles/nginx/files/genssl.sh

#------------------------------
# Deploy OpenWhisk
#------------------------------
echo "Deploy OpenWhisk"
cd ${HOME}/openwhisk/ansible
ansible-playbook setup.yml
ansible-playbook prereq.yml
ansible-playbook couchdb.yml
ansible-playbook initdb.yml
ansible-playbook wipe.yml
ansible-playbook openwhisk.yml
ansible-playbook postdeploy.yml
echo "OpenWhisk deployment complete"
echo ""

#------------------------------
# Add OpenWhisk cert as trusted
#------------------------------
echo "Adding OpenWhisk cert"
cp ${HOME}/openwhisk/ansible/roles/nginx/files/openwhisk-cert.pem /usr/local/share/ca-certificates/openwhisk-cert.crt
#ln -s /usr/local/share/ca-certificates/openwhisk-cert.pem /etc/ssl/certs/openwhisk-cert.pem || true
update-ca-certificates

#------------------------------
# Fix path for wsk cmds
#------------------------------
echo "Adding OpenWhisk binary links"
ln -s ${HOME}/openwhisk/bin/wsk /usr/bin/wsk || true
ln -s ${HOME}/openwhisk/bin/wskadmin /usr/bin/wskadmin || true

#echo 'alias wsk="wsk -i"' >> ${HOME}/.bash_aliases
echo "export PATH=${HOME}/openwhisk/bin:${PATH}" >> ${HOME}/.bashrc
source ${HOME}/.bashrc
chown -R ${USER}:${USER} ${HOME}/

#------------------------------
# Setup OpenWhisk CLI https://github.com/openwhisk/openwhisk/blob/master/docs/cli.md
#------------------------------
echo "Setting up OpenWhisk CLI"
# Set apihost
apihost=$(grep 'edge.host=' ${HOME}/openwhisk/whisk.properties | cut -d '=' -f2) || true
wsk property set --apihost ${apihost}
#wsk property set --apihost localhost

#------------------------------
# Test OpenWhisk
#------------------------------
echo "Testing OpenWhisk"
# Get auth for whisk.system
wsk action invoke /whisk.system/utils/echo -p message hello --blocking --result --auth `cat ${HOME}/openwhisk/ansible/files/auth.guest`
echo ""

exit 0
