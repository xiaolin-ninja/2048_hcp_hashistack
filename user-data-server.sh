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

# echo "Checking latest Consul and Nomad versions..."
# CHECKPOINT_URL="https://checkpoint-api.hashicorp.com/v1/check"
# CONSUL_VERSION=$(curl -s "$${CHECKPOINT_URL}"/consul | jq -r .current_version)
# NOMAD_VERSION=$(curl -s "$${CHECKPOINT_URL}"/nomad | jq -r .current_version)
NOMAD_VERSION=1.5.3
CONSUL_VERSION=1.15.2
VAULT_VERSION=1.13.1

cd /tmp/

echo "Fetching Vault version $${VAULT_VERSION} ..."
curl -s https://releases.hashicorp.com/vault/$${VAULT_VERSION}/vault_$${VAULT_VERSION}_linux_amd64.zip -o vault.zip
echo "Installing Vault version $${VAULT_VERSION} ..."
unzip vault.zip
chmod +x vault
mv vault /usr/local/bin/vault

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
# Vault Agent config
########

sudo mkdir -p /opt/nomad/templates
cat << EONT >/opt/nomad/templates/agent.crt.tpl
{{ with secret "pki_int/issue/nomad-cluster" "common_name=server.global.nomad" "ttl=24h" "alt_names=localhost,server.${nomad_region}.nomad" "ip_sans=127.0.0.1"}}
{{ .Data.certificate }}
{{ end }}
EONT

cat << EONT >/opt/nomad/templates/agent.key.tpl
{{ with secret "pki_int/issue/nomad-cluster" "common_name=server.global.nomad" "ttl=24h" "alt_names=localhost,server.${nomad_region}.nomad" "ip_sans=127.0.0.1"}}
{{ .Data.private_key }}
{{ end }}
EONT

cat << EONT >/opt/nomad/templates/ca.crt.tpl
{{ with secret "pki_int/issue/nomad-cluster" "common_name=server.global.nomad" "ttl=24h" "alt_names=localhost,server.${nomad_region}.nomad"}}
{{ .Data.issuing_ca }}
{{ end }}
EONT

mkdir -p /etc/vault-agent.d
VAULT_TOKEN_PATH=/home/ubuntu/vault-token-via-agent

cat << EOVAC >/etc/vault-agent.d/vault-agent.hcl
exit_after_auth = false
pid_file = "./pidfile"

auto_auth {
  method "aws" {
      mount_path = "auth/aws"
      namespace = "admin"
      config = {
          type = "iam"
          role = "${aws_role}"
      }
  }

  sink "file" {
      wrap_ttl = "30m"
      config = {
          path = "$VAULT_TOKEN_PATH"
      }
  }
}

template_config {
  exit_on_retry_failure = true
  static_secret_render_interval = "10m"
}
template {
  source      = "/opt/nomad/templates/agent.crt.tpl"
  destination = "/opt/nomad/agent-certs/agent.crt"
  perms       = 0700
  command     = "systemctl reload nomad"
}
template {
  source      = "/opt/nomad/templates/agent.key.tpl"
  destination = "/opt/nomad/agent-certs/agent.key"
  perms       = 0700
  command     = "systemctl reload nomad"
}

template {
  source      = "/opt/nomad/templates/ca.crt.tpl"
  destination = "/opt/nomad/agent-certs/ca.crt"
  command     = "systemctl reload nomad"
}

# The following template stanzas are for the CLI certs

# template {
#   source      = "/opt/nomad/templates/cli.crt.tpl"
#   destination = "/opt/nomad/cli-certs/cli.crt"
# }

# template {
#   source      = "/opt/nomad/templates/cli.key.tpl"
#   destination = "/opt/nomad/cli-certs/cli.key"
# }

vault {
  address = "${vault_endpoint}"
}

EOVAC

# mkdir -p /var/lib/vault

cat << EOCSU >/etc/systemd/system/vault-agent.service
[Unit]
Description="HashiCorp Vault Agent - Secure Identity Introduction"
Documentation=https://www.vaultproject.io/
Requires=network-online.target
After=network-online.target
[Service]
Type=notify
ExecStart=/usr/local/bin/vault agent -config /etc/vault-agent.d/vault-agent.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGTERM
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOCSU

systemctl daemon-reload
systemctl start vault-agent
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
Requires=network-online.target vault-agent.service
After=network-online.target vault-agent.service
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
while [ ! -f $VAULT_TOKEN_PATH ]
do
  sleep 2 
done

export VAULT_ADDR=${vault_endpoint}
export VAULT_NAMESPACE=admin
VAULT_TOKEN=$(vault unwrap -field=token $(jq -r '.token' $VAULT_TOKEN_PATH))
cat << EONEF >/etc/default/nomad
CONSUL_HTTP_TOKEN=${consul_acl_token}
VAULT_NAMESPACE=admin
VAULT_TOKEN=$VAULT_TOKEN
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
tls {
  http = true
  rpc  = true

  ca_file   = "/opt/nomad/agent-certs/ca.crt"
  cert_file = "/opt/nomad/agent-certs/agent.crt"
  key_file  = "/opt/nomad/agent-certs/agent.key"

  verify_server_hostname = true
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
Requires=network-online.target consul.service vault-agent.service
After=network-online.target consul.service vault-agent.service
[Service]
LimitNOFILE=65536
Restart=on-failure
EnvironmentFile=/etc/default/nomad
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
ExecReload=/bin/kill --signal HUP $MAINPID
KillSignal=SIGINT
RestartSec=5s
[Install]
WantedBy=multi-user.target
EONSU

systemctl daemon-reload
systemctl start consul
systemctl start nomad
