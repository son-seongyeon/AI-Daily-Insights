#!/bin/bash

# Install Python 3.8 and required libraries for nlp_analyzer.py
amazon-linux-extras enable python3.8
yum install python38 python38-pip -y
pip3.8 install boto3 openai pymysql pandas

# Install FastAPI and Uvicorn for backend API
yum install -y python3 python3-pip mariadb
pip3 install fastapi uvicorn

# Create application directory
mkdir -p /root/app
cd /root/app

# Create FastAPI app
cat << 'EOF' > app.py
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}
EOF

# Create systemd service
cat << 'EOF' > /etc/systemd/system/fastapi.service
[Unit]
Description=FastAPI Server
After=network.target

[Service]
User=root
WorkingDirectory=/root/app
ExecStart=/usr/bin/python3 -m uvicorn app:app --host 0.0.0.0 --port 80
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the FastAPI service
systemctl daemon-reload
systemctl enable fastapi
systemctl start fastapi