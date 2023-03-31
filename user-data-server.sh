#!/bin/bash
# This script is meant to be run in the User Data of each EC2 Instance while it's booting.
set -e
set -x

export TERM=xterm-256color
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    jq \
    unzip

echo "Checking latest Consul and Nomad versions..."
CHECKPOINT_URL="https://checkpoint-api.hashicorp.com/v1/check"
CONSUL_VERSION=$(curl -s "$${CHECKPOINT_URL}"/consul | jq -r .current_version)
NOMAD_VERSION=$(curl -s "$${CHECKPOINT_URL}"/nomad | jq -r .current_version)

cd /tmp/

echo "Fetching Consul version $${CONSUL_VERSION} ..."
curl -s https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip -o consul.zip
echo "Installing Consul version $${CONSUL_VERSION} ..."
unzip consul.zip
chmod +x consul
mv consul /usr/local/bin/consul

echo "Fetching Nomad version $${NOMAD_VERSION} ..."
curl -s https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip -o nomad.zip
echo "Installing Nomad version $${NOMAD_VERSION} ..."
unzip nomad.zip
chmod +x nomad
mv nomad /usr/local/bin/nomad

########
# Consul config
########

mkdir -p /etc/consul.d
mkdir -p /var/lib/consul
cat << EOCCF >/etc/consul.d/client.json
${consul_config_file}
EOCCF

cat << EOCCF >/etc/consul.d/client_extra.hcl
"tls" = {
  "defaults" = {
    "ca_file" = "/var/lib/consul/ca.pem"
    }
}
"data_dir" = "/var/lib/consul"
EOCCF

cat << EOCACF >/etc/consul.d/acl.hcl
acl = {
    tokens = {
        agent = "${consul_acl_token}"
    }
}
EOCACF

cat << EOCCA >/var/lib/consul/ca.pem
${consul_ca_file}
EOCCA


cat << EOCSU >/etc/systemd/system/consul.service
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
[Service]
Type=notify
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/ -advertise '{{ GetAllInterfaces | include "name" "^ens" | include "flags" "forwardable|up" | attr "address" }}'
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOCSU

##########
# Nomad config
##########

cat << EONEF >/etc/default/nomad
CONSUL_HTTP_TOKEN=${consul_acl_token}
VAULT_NAMESPACE=admin
VAULT_TOKEN=${vault_token}
EONEF

mkdir -p /etc/nomad.d/
cat << EONCF >/etc/nomad.d/server.hcl
bind_addr          = "0.0.0.0"
region             = "${nomad_region}"
datacenter         = "${nomad_datacenter}"
data_dir           = "/var/lib/nomad/"
log_level          = "DEBUG"
leave_on_interrupt = true
leave_on_terminate = true
server {
  enabled          = true
  bootstrap_expect = 1
}
acl {
  enabled    = true
  token_ttl  = "30s"
  policy_ttl = "60s"
  role_ttl   = "60s"
}
EONCF

cat << EONVF >/etc/nomad.d/vault.hcl
vault {
  enabled          = true
  address          = "${vault_endpoint}"
  create_from_role = "nomad-cluster"
}
EONVF

cat << EONSU >/etc/systemd/system/nomad.service
[Unit]
Description=nomad agent
Requires=network-online.target consul.service
After=network-online.target consul.service
[Service]
LimitNOFILE=65536
Restart=on-failure
EnvironmentFile=/etc/default/nomad
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
KillSignal=SIGINT
RestartSec=5s
[Install]
WantedBy=multi-user.target
EONSU

systemctl daemon-reload
systemctl start consul
systemctl start nomad
