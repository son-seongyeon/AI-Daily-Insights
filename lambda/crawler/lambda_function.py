import json
import boto3
import requests
from bs4 import BeautifulSoup
import csv
from datetime import datetime

# AWS Clients
s3 = boto3.client("s3")
ssm = boto3.client("ssm")
sns = boto3.client("sns")

# ====================================
# CONFIG
# ====================================
BUCKET_NAME = "my-ai-daily-insights-s3"

QUERIES = [
    "AI", "Artificial Intelligence", "LLM",
    "AI Cloud", "Autonomous Driving"
]

BASE_URL = "https://search.naver.com/search.naver"
HEADERS = {"User-Agent": "Mozilla/5.0"}

TARGET_TAG_KEY = "Role"
TARGET_TAG_VALUE = "nlp-analyzer"

SNS_TOPIC_ARN = "arn:aws:sns:ap-northeast-2:442426894130:ai-daily-insights-alert"
LOG_GROUP_NAME = "/app-ec2/nlp-analyzer/logs"


# ====================================
# SNS Notification Format
# ====================================
def send_sns_notification(status, s3_key, command_id):
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

    message = f"""
==============================
📌 Daily NLP Pipeline Status
==============================

🟢 Status: {status}

📁 Saved CSV:
{s3_key}

⚙️ Analyzer Command ID:
{command_id}

⏱ Time:
{now}

"""

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[{status}] Daily NLP Pipeline",
        Message=message
    )


# ====================================
# Extract Naver News Link
# ====================================
def extract_news_link(item):
    for a in item.find_all("a"):
        if a.get_text(strip=True) == "네이버뉴스":
            return a["href"]
    return None


# ====================================
# Get Full Article Content
# ====================================
def get_news_content(link):
    try:
        res = requests.get(link, headers=HEADERS, timeout=5)
        soup = BeautifulSoup(res.text, "html.parser")
        article = soup.select_one("#dic_area")
        return article.get_text("\n", strip=True) if article else "No Content Found"
    except:
        return "Failed to Load Article"


# ====================================
# Lambda Handler
# ====================================
def lambda_handler(event, context):

    print("===== Starting Multi-Keyword Naver News Crawling =====")

    all_titles = []
    all_links = []
    all_contents = []
    all_presses = []
    all_dates = []
    seen_titles = {}

    # --------------------------
    # Crawling for each keyword
    # --------------------------
    for query in QUERIES:
        print(f"--- Searching [{query}] ---")

        params = {
            "where": "news",
            "query": query,
            "sort": 0,          # Relevant Results
            "nso": "so:r,p:1d"  # Last 1 Day
        }

        try:
            response = requests.get(BASE_URL, params=params, headers=HEADERS, timeout=5)
            soup = BeautifulSoup(response.text, "html.parser")
        except Exception as e:
            print(f"Request error: {e}")
            continue

        news_items = soup.select("div.sds-comps-vertical-layout.sds-comps-full-layout")

        for item in news_items:
            try:
                # Title
                title_tag = item.select_one(
                    'a._228e3bd1 span.sds-comps-text-type-headline1'
                )
                title = title_tag.get_text(strip=True) if title_tag else ""
                if not title:
                    continue

                # Deduplicate titles
                if title in seen_titles:
                    idx = seen_titles[title]
                    new_link = extract_news_link(item)
                    if new_link:
                        all_links[idx] = new_link
                    continue

                # Link
                link = extract_news_link(item)
                if not link:
                    continue

                # Press
                press_tag = item.select_one(
                    'div.sds-comps-profile-info-title span.sds-comps-text-type-body2'
                )
                press = press_tag.get_text(strip=True) if press_tag else "Unknown Press"

                # Date
                time_tag = item.select_one(
                    'span.sds-comps-profile-info-subtext span.sds-comps-text-type-body2'
                )
                upload_time = time_tag.get_text(strip=True) if time_tag else "Unknown Date"

                # Article Content
                content = get_news_content(link)

                # Save metadata
                seen_titles[title] = len(all_titles)
                all_titles.append(title)
                all_links.append(link)
                all_contents.append(content)
                all_presses.append(press)
                all_dates.append(upload_time)

                print(f"Collected: {title}")

            except Exception as e:
                print(f"Error parsing item: {e}")

    # ============================================
    # Save as CSV
    # ============================================
    timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    local_path = f"/tmp/NaverNews_AITrends_{timestamp}.csv"
    s3_key = f"raw/NaverNews_AITrends_{timestamp}.csv"

    with open(local_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(["title", "link", "content", "press", "date"])
        for i in range(len(all_titles)):
            writer.writerow([
                all_titles[i],
                all_links[i],
                all_contents[i],
                all_presses[i],
                all_dates[i]
            ])

    print(f"Local CSV saved: {local_path}")

    # Upload to S3
    s3.upload_file(local_path, BUCKET_NAME, s3_key)
    print(f"Uploaded to S3: s3://{BUCKET_NAME}/{s3_key}")

    # ============================================
    # Trigger SSM Run Command → NLP Analyzer
    # ============================================
    print("Triggering SSM Run Command for Analyzer EC2 instances...")

    response = ssm.send_command(
        Targets=[
            {
                "Key": f"tag:{TARGET_TAG_KEY}",
                "Values": [TARGET_TAG_VALUE]
            }
        ],
        DocumentName="AWS-RunShellScript",
        Parameters={
            "commands": [
                "python3.8 /root/analyzer/nlp_analyzer.py"
            ]
        },
        CloudWatchOutputConfig={
            "CloudWatchOutputEnabled": True,
            "CloudWatchLogGroupName": LOG_GROUP_NAME
        }
    )

    command_id = response["Command"]["CommandId"]

    print(f"RunCommand triggered. CommandId = {command_id}")

    # ============================================
    # SNS Success Notification
    # ============================================
    send_sns_notification(
        status="SUCCESS",
        s3_key=s3_key,
        command_id=command_id
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "success",
            "s3_key": s3_key,
            "command_id": command_id
        })
    }