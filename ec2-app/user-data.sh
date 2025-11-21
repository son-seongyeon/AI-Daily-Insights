#!/bin/bash

# Install Python 3.8 and required libraries for NLP analyzer
amazon-linux-extras enable python3.8
yum install -y python38 python38-pip
pip3.8 install boto3 openai pymysql pandas requests beautifulsoup4

# Install FastAPI, Uvicorn, MariaDB client
yum install -y python3 python3-pip mariadb
pip3 install fastapi uvicorn

# Create FastAPI application directory
mkdir -p /root/app
cd /root/app

# Create FastAPI application
cat << 'EOF' > app.py
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}
EOF

# Create systemd service for FastAPI
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

# Enable and start FastAPI service
systemctl daemon-reload
systemctl enable fastapi
systemctl start fastapi

# Create NLP analyzer directory
mkdir -p /root/analyzer
cd /root/analyzer

# Create nlp_analyzer.py
cat << 'EOF' > /root/analyzer/nlp_analyzer.py
import boto3
import pandas as pd
from openai import OpenAI
import pymysql
from datetime import datetime

# S3 client setup
s3 = boto3.client('s3')
BUCKET_NAME = "my-ai-daily-insights-s3"
PREFIX = "raw/"

# RDS connection setup
def get_connection():
    return pymysql.connect(
        host="my-db.cx28scimshga.ap-northeast-2.rds.amazonaws.com",
        user="admin",
        password="password",
        db="insightdb",
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True
    )

# Load latest file from S3
def get_latest_s3_file():
    obj = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=PREFIX)
    files = sorted(obj["Contents"], key=lambda x: x["LastModified"], reverse=True)
    latest = files[0]["Key"]
    print(f"[INFO] Latest CSV: {latest}")
    return latest

# Load CSV into DataFrame
def load_csv_from_s3(key):
    obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
    df = pd.read_csv(obj["Body"], encoding="utf-8")
    print(f"[INFO] Loaded articles count = {len(df)}")
    return df

# OpenAI configuration
client = OpenAI(api_key="API_KEY")

# Generate summary (1 sentence)
def generate_summary(big_text):
    prompt = f"""
Below is a collection of AI-related article texts gathered today.
Based on these, generate a single-sentence summary representing today's major AI/IT trend.

Requirements:
- 1 sentence in English
- Clear and concise

Article text:
{big_text}
"""
    response = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": "You are an analyst specializing in IT trends."},
            {"role": "user", "content": prompt}
        ]
    )
    return response.choices[0].message.content.strip()

# Extract 5 keywords
def generate_keywords(big_text):
    prompt = f"""
Below is a collection of AI-related article texts gathered today.
Extract 5 keywords that represent today's AI/IT trends.

Requirements:
- 5 English keywords
- Only return a comma-separated string

Article text:
{big_text}
"""
    response = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": "You are an expert keyword extraction analyst."},
            {"role": "user", "content": prompt}
        ]
    )
    return response.choices[0].message.content.strip()

# Generate AI insight paragraph
def generate_insight(big_text):
    prompt = f"""
Below is a collection of AI-related article texts gathered today.
Analyze the content and generate a 'Daily AI Insight' summarizing today's overall AI/IT trend.

Requirements:
- Written in English
- 5–8 full sentences
- Provide a logical and natural summary

Article text:
{big_text}
"""
    response = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": "You are an expert insight analyst for AI/IT news."},
            {"role": "user", "content": prompt}
        ]
    )
    return response.choices[0].message.content.strip()

# Save insight into RDS
def save_daily_insight(summary, keywords, insight):
    conn = get_connection()
    sql = "INSERT INTO insights (summary, keywords, insight) VALUES (%s, %s, %s)"
    with conn.cursor() as cursor:
        cursor.execute(sql, (summary, keywords, insight))
    conn.close()
    print("[INFO] Insight saved!")

# Save article metadata into RDS
def save_articles(df):
    conn = get_connection()
    sql = "INSERT INTO articles (title, link) VALUES (%s, %s)"
    with conn.cursor() as cursor:
        for _, row in df.iterrows():
            cursor.execute(sql, (row["title"], row["link"]))
    conn.close()
    print("[INFO] Articles saved!")

# Main pipeline
def main():
    latest_file = get_latest_s3_file()
    df = load_csv_from_s3(latest_file)

    contents = df["content"].tolist()
    combined_text = "\n".join(contents)

    print("[INFO] Generating summary...")
    summary = generate_summary(combined_text)

    print("[INFO] Generating keywords...")
    keywords = generate_keywords(combined_text)

    print("[INFO] Generating insight...")
    insight = generate_insight(combined_text)

    save_daily_insight(summary, keywords, insight)
    save_articles(df)

    print("\n[INFO] Completed!")
    print("Summary:", summary)
    print("Keywords:", keywords)
    print("Insight:", insight)

if __name__ == "__main__":
    main()
EOF

echo "Setup completed: FastAPI and NLP Analyzer installed successfully."