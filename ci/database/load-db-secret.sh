#!/usr/bin/env bash
# Sourced by migrate.sh after AWS authentication. Keep secret values in memory.
set +x
# Report only recognized error categories; never echo AWS response/error bodies.
db_secret_error_hint() {
  awk '
    /AccessDeniedException|AccessDenied/ {
      print "AWS AccessDenied: Check the assumed role has secretsmanager:GetSecretValue on this secret, its resource policy, and kms:Decrypt if using a customer-managed key."; next
    }
    /ResourceNotFoundException/ {
      print "AWS ResourceNotFound: Check DB_SECRET_ID, AWS_REGION, and the AWS account of the assumed role. Use the full ARN for a cross-account secret."; next
    }
    /ExpiredToken|InvalidClientTokenId|UnrecognizedClientException|Unable to locate credentials/ {
      print "AWS authentication failed: Check the OIDC authentication step and temporary AWS credentials."; next
    }
    /DecryptionFailure/ {
      print "AWS DecryptionFailure: Check the secrets encryption key and KMS permissions."; next
    }
    /InvalidRequestException/ {
      print "AWS InvalidRequest: Check whether the secret is scheduled for deletion or otherwise unavailable."; next
    }
    /Could not connect to the endpoint URL|Connect timeout|Read timeout|SSL validation failed|Failed to connect to proxy/ {
      print "AWS connection failed: Check runner access to Secrets Manager, AWS_REGION, proxy settings, and TLS trust."; next
    }
    /command not found/ {
      print "AWS CLI is unavailable: Run ci/common/install-tools.sh aws before migration."; next
    }
  '
}
DB_SECRET_JSON="$(aws secretsmanager get-secret-value \
  --secret-id "${DB_SECRET_ID}" --region "${AWS_REGION}" \
  --query SecretString --output text 2> >(db_secret_error_hint >&2))" || {
  echo "ERROR: Could not retrieve the database secret from AWS Secrets Manager." >&2
  exit 1
}

# Key mappings are configuration, not credentials. Defaults match RDS secrets.
DB_CONNECTION_JSON="$(printf '%s' "${DB_SECRET_JSON}" | jq -ce \
  --arg host "${DB_SECRET_HOST_KEY:-host}" \
  --arg database "${DB_SECRET_DATABASE_KEY:-database}" \
  --arg username "${DB_SECRET_USERNAME_KEY:-username}" \
  --arg password "${DB_SECRET_PASSWORD_KEY:-password}" \
  --arg port "${DB_SECRET_PORT_KEY:-port}" '
    {host: .[$host], database: .[$database], username: .[$username],
     password: .[$password], port: (.[$port] // 5432)}
    | select(all(.host, .database, .username, .password;
        type == "string" and length > 0 and (contains("\u0000") | not)))
    | select(.host | test("^[A-Za-z0-9][A-Za-z0-9.-]*$"))
    | .port |= tostring
    | select(.port | test("^[0-9]+$"))
    | select((.port | tonumber) >= 1 and (.port | tonumber) <= 65535)
  ' 2>/dev/null)" || {
  echo "ERROR: Database secret must contain valid host, database, username, password, and optional port fields. Check DB_SECRET_*_KEY mappings." >&2
  exit 1
}
unset DB_SECRET_JSON

case "${DB_SSLMODE:-require}" in
  disable|allow|prefer|require|verify-ca|verify-full) ;;
  *) echo "ERROR: Invalid DB_SSLMODE." >&2; exit 1 ;;
esac
LIQUIBASE_COMMAND_URL="$(printf '%s' "${DB_CONNECTION_JSON}" | jq -r \
  --arg sslmode "${DB_SSLMODE:-require}" \
  '"jdbc:postgresql://\(.host):\(.port)/\(.database | @uri)?sslmode=\($sslmode)"')"
# A sentinel preserves any trailing newlines in credentials during substitution.
LIQUIBASE_COMMAND_USERNAME="$(printf '%s' "${DB_CONNECTION_JSON}" | jq -j '.username + "."')"
LIQUIBASE_COMMAND_USERNAME="${LIQUIBASE_COMMAND_USERNAME%.}"
LIQUIBASE_COMMAND_PASSWORD="$(printf '%s' "${DB_CONNECTION_JSON}" | jq -j '.password + "."')"
LIQUIBASE_COMMAND_PASSWORD="${LIQUIBASE_COMMAND_PASSWORD%.}"
unset DB_CONNECTION_JSON
