provider "vault" {
  address                = hcp_vault_cluster.xx_2048_vault.vault_public_endpoint_url
  namespace              = "admin"
  token                  = hcp_vault_cluster_admin_token.xx_2048_vault_token.token
  skip_child_token       = true
  skip_get_vault_version = true
}

data "http" "nomad_server_policy" {
  url = "https://nomadproject.io/data/vault/nomad-server-policy.hcl"
}

resource "vault_policy" "nomad-server" {
  name   = "nomad-server"
  policy = data.http.nomad_server_policy.response_body
  depends_on = [
    hcp_vault_cluster.xx_2048_vault
  ]
}

resource "vault_token_auth_backend_role" "nomad-cluster" {
  role_name              = "nomad-cluster"
  disallowed_policies    = ["nomad-server"]
  orphan                 = true
  token_period           = "259200"
  renewable              = true
  token_explicit_max_ttl = 0
  depends_on = [
    hcp_vault_cluster.xx_2048_vault
  ]
}

#---------------------------------------------------------------------------------------------------------------------
# Vault PKI
# ---------------------------------------------------------------------------------------------------------------------

resource "vault_mount" "pki" {
  path                  = "pki"
  type                  = "pki"
  max_lease_ttl_seconds = 315360000
}
resource "vault_pki_secret_backend_root_cert" "nomad_root" {
  depends_on   = [vault_mount.pki]
  backend      = vault_mount.pki.path
  type         = "internal"
  common_name  = "global.nomad"
  ttl          = "87600h"
  key_type     = "rsa"
  key_bits     = 4096
  organization = "HashiCorp"
}

resource "vault_mount" "pki_int" {
  depends_on  = [vault_mount.pki]
  path                  = "pki_int"
  type                  = "pki"
  max_lease_ttl_seconds = 157680000
}
resource "vault_pki_secret_backend_intermediate_cert_request" "nomad_int" {
  depends_on  = [vault_mount.pki]
  backend     = vault_mount.pki_int.path
  type        = "internal"
  key_type     = "rsa"
  key_bits     = 4096
  common_name = "global.nomad Intermediate Authority"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "nomad_root" {
  backend     = vault_mount.pki.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.nomad_int.csr
  format      = "pem"
  common_name = "global.nomad Intermediate Authority"
  ttl         = "43800h"

}

resource "vault_pki_secret_backend_intermediate_set_signed" "nomad_int" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.nomad_root.certificate
}

resource "vault_pki_secret_backend_role" "role" {
  backend          = vault_mount.pki_int.path
  name             = "nomad-cluster"
  max_ttl          = 86400
  allow_ip_sans    = true
  key_type         = "rsa"
  key_bits         = 4096
  allowed_domains  = ["global.nomad", ".nomad", "${data.aws_region.current.name}.nomad"]
  allow_subdomains = true
  require_cn       = false
  generate_lease   = true
}

resource "vault_policy" "nomad-tls-policy" {
  name   = "nomad-tls-policy"
  policy = <<EOF
path "pki_int/issue/nomad-cluster" {
  capabilities = ["update"]
}
EOF
  depends_on = [
    hcp_vault_cluster.xx_2048_vault
  ]
}

# AWS auth for clients and agents
resource "aws_iam_user" "vault_auth" {
  name = "aws-iamuser-for-vault-authmethod"
}

resource "aws_iam_user_policy" "vault_auth" {
  name   = "aws-iampolicy-for-vault-authmethod"
  user   = aws_iam_user.vault_auth.name
  policy = <<EOP
{
"Version": "2012-10-17",
"Statement": [
 {
   "Effect": "Allow",
   "Action": [
     "ec2:DescribeInstances",
     "iam:GetInstanceProfile",
     "iam:GetUser",
     "iam:ListRoles",
     "iam:GetRole"
   ],
   "Resource": "*"
 }
 ]
}
EOP
}

resource "aws_iam_access_key" "vault_mount_user" {
  user = aws_iam_user.vault_auth.name
}

resource "vault_auth_backend" "aws" {
  type = "aws"
}
resource "vault_aws_auth_backend_client" "aws_client" {
  backend    = vault_auth_backend.aws.path
  access_key = aws_iam_access_key.vault_mount_user.id
  secret_key = aws_iam_access_key.vault_mount_user.secret
}

# resource "vault_generic_endpoint" "rotate_initial_aws_credentials" {
#   depends_on           = [vault_aws_auth_backend_client.aws_client]
#   path                 = "${vault_auth_backend.aws.path}/config/rotate-root"
#   disable_read   = true
#   disable_delete = true

#   data_json = "{}"
# }

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nomad_client" {
  name               = "nomad-client-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_instance_profile" "nomad_client" {
  name = "nomad_client"
  role = aws_iam_role.nomad_client.name
}

resource "aws_iam_role" "nomad_server" {
  name               = "nomad-server-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}
resource "aws_iam_instance_profile" "nomad_server" {
  name = "nomad_server"
  role = aws_iam_role.nomad_server.name
}

resource "vault_aws_auth_backend_role" "nomad_client" {
  backend                  = vault_auth_backend.aws.path
  role                     = "nomad_client"
  auth_type                = "iam"
  bound_iam_principal_arns = [aws_iam_role.nomad_client.arn]

  token_policies = [vault_policy.nomad-tls-policy.name]
  token_period   = 1800
}

resource "vault_aws_auth_backend_role" "nomad_server" {
  backend                  = vault_auth_backend.aws.path
  role                     = "nomad_server"
  auth_type                = "iam"
  bound_iam_principal_arns = [aws_iam_role.nomad_server.arn]

  token_policies = [vault_policy.nomad-tls-policy.name,
    vault_policy.nomad-server.name
  ]
  token_period = 1800
}

