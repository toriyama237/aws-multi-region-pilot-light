#!/bin/bash
set -euxo pipefail

dnf install -y python3.11 python3.11-pip git jq

git clone --depth 1 ${repo_url} /opt/notes
python3.11 -m venv /opt/notes/venv
/opt/notes/venv/bin/pip install --no-cache-dir -r /opt/notes/app/requirements.txt

# Credentials come from Secrets Manager at boot, never from user data or
# the AMI. The secret name is the same in both regions because the
# secret is natively replicated, so this script is region-agnostic.
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_name}" \
  --region "${region}" \
  --query SecretString --output text)

install -m 600 /dev/null /etc/notes-api.env
cat > /etc/notes-api.env <<ENV
DB_HOST=${db_host}
DB_PORT=$(echo "$SECRET" | jq -r .port)
DB_NAME=$(echo "$SECRET" | jq -r .dbname)
DB_USER=$(echo "$SECRET" | jq -r .username)
DB_PASSWORD=$(echo "$SECRET" | jq -r .password)
APP_REGION=${region}
ENV

cat > /etc/systemd/system/notes-api.service <<'UNIT'
[Unit]
Description=Notes API
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/notes-api.env
WorkingDirectory=/opt/notes/app
ExecStart=/opt/notes/venv/bin/uvicorn notes_api.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now notes-api
