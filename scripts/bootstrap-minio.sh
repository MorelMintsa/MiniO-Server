#!/bin/sh
set -eu

: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
: "${MINIO_BUCKETS:?MINIO_BUCKETS is required}"

MINIO_ENDPOINT="${MINIO_ENDPOINT:-https://s3-minio.gotherdev.online}"
MINIO_POLICY_NAME="${MINIO_POLICY_NAME:-app-buckets-rw}"
MC_CONFIG_DIR="${MC_CONFIG_DIR:-/tmp/.mc}"

export MC_CONFIG_DIR
mkdir -p "$MC_CONFIG_DIR"

mc alias set local "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null

bucket_names="$(printf '%s' "$MINIO_BUCKETS" | tr ',' ' ')"

validate_bucket_name() {
  bucket="$1"
  length="${#bucket}"

  if [ "$length" -lt 3 ] || [ "$length" -gt 63 ]; then
    echo "Invalid bucket name: $bucket" >&2
    exit 1
  fi

  case "$bucket" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789.-]* | .* | *.)
    echo "Invalid bucket name: $bucket" >&2
    exit 1
      ;;
  esac
}

for bucket in $bucket_names; do
  validate_bucket_name "$bucket"

  if [ "${MINIO_BUCKET_OBJECT_LOCK:-false}" = "true" ]; then
    mc mb --ignore-existing --with-lock "local/$bucket"
  else
    mc mb --ignore-existing "local/$bucket"
  fi

  if [ "${MINIO_ENABLE_VERSIONING:-false}" = "true" ]; then
    mc version enable "local/$bucket"
  fi

  if [ -n "${MINIO_BUCKET_QUOTA:-}" ]; then
    mc quota set "local/$bucket" --size "$MINIO_BUCKET_QUOTA"
  fi
done

if [ -n "${MINIO_APP_USER:-}" ] && [ -n "${MINIO_APP_PASSWORD:-}" ]; then
  if [ "$MINIO_APP_USER" = "$MINIO_ROOT_USER" ]; then
    echo "Skipping application user creation: MINIO_APP_USER must be different from MINIO_ROOT_USER." >&2
    echo "Set MINIO_APP_USER to a dedicated service account for restricted bucket access." >&2
    mc ls local
    exit 0
  fi

  if ! mc admin user info local "$MINIO_APP_USER" >/dev/null 2>&1; then
    mc admin user add local "$MINIO_APP_USER" "$MINIO_APP_PASSWORD"
  fi

  bucket_resources=""
  object_resources=""
  separator=""

  for bucket in $bucket_names; do
    bucket_resources="${bucket_resources}${separator}\"arn:aws:s3:::${bucket}\""
    object_resources="${object_resources}${separator}\"arn:aws:s3:::${bucket}/*\""
    separator=","
  done

  cat > /tmp/minio-app-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListAllMyBuckets"],
      "Resource": ["arn:aws:s3:::*"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": [${bucket_resources}]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [${object_resources}]
    }
  ]
}
EOF

  mc admin policy create local "$MINIO_POLICY_NAME" /tmp/minio-app-policy.json
  mc admin policy attach local "$MINIO_POLICY_NAME" --user "$MINIO_APP_USER"
fi

mc ls local
