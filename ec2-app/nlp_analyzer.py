import boto3
import pandas as pd
from openai import OpenAI
import pymysql
from datetime import datetime

# -----------------------------
# 1. AWS S3 client setup
# -----------------------------
s3 = boto3.client('s3')

BUCKET_NAME = "my-ai-daily-insights-s3"
PREFIX = "raw/"


# -----------------------------
# 2. RDS connection setup
# -----------------------------
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


# -----------------------------
# 3. Load latest CSV from S3
# -----------------------------
def get_latest_s3_file():
    obj = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=PREFIX)
    files = sorted(obj["Contents"], key=lambda x: x["LastModified"], reverse=True)
    latest = files[0]["Key"]
    print(f"[INFO] Latest CSV: {latest}")
    return latest


def load_csv_from_s3(key):
    obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
    df = pd.read_csv(obj["Body"], encoding="utf-8")
    print(f"[INFO] Loaded articles count = {len(df)}")
    return df


# -----------------------------
# 4. OpenAI client setup
# -----------------------------
client = OpenAI(
    api_key="API_KEY"
)


# -----------------------------
# 5. NLP generation functions
# -----------------------------
def generate_summary(big_text):
    # Generates a one-sentence summary of daily AI/IT trends
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
            {"role": "system", "content": "You are an analyst specializing in Korean IT trends."},
            {"role": "user", "content": prompt}
        ]
    )
    return response.choices[0].message.content.strip()


def generate_keywords(big_text):
    # Extracts 5 keywords
    prompt = f"""
Below is a collection of AI-related article texts gathered today.
Extract 5 keywords that represent today's AI/IT trends.

Requirements:
- 5 keywords in English
- Return only a comma-separated string

Article text:
{big_text}
"""
    response = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": "You are an analyst specializing in Korean IT trend keywords."},
            {"role": "user", "content": prompt}
        ]
    )
    return response.choices[0].message.content.strip()


def generate_insight(big_text):
    # Generates a 5–8 sentence insight paragraph
    prompt = f"""
Below is a collection of AI-related article texts gathered today.
Analyze the content and generate a 'Daily AI Insight' summarizing today's overall AI/IT trend.

Requirements:
- Written in English
- 5–8 full sentences
- Provide a logical and natural summary of the daily trend

Article text:
{big_text}
"""
    response = client.chat.completions.create(
        model="o3-mini",
        messages=[
            {"role": "system", "content": "You are an expert analyst of Korean AI/IT news insights."},
            {"role": "user", "content": prompt}
        ]
    )
    return response.choices[0].message.content.strip()


# -----------------------------
# 6. Save results into RDS
# -----------------------------
def save_daily_insight(summary, keywords, insight):
    conn = get_connection()
    sql = "INSERT INTO insights (summary, keywords, insight) VALUES (%s, %s, %s)"
    with conn.cursor() as cursor:
        cursor.execute(sql, (summary, keywords, insight))
    conn.close()
    print("[INFO] Insight saved!")


def save_articles(df):
    conn = get_connection()
    sql = "INSERT INTO articles (title, link) VALUES (%s, %s)"
    with conn.cursor() as cursor:
        for _, row in df.iterrows():
            cursor.execute(sql, (row["title"], row["link"]))
    conn.close()
    print("[INFO] Articles saved!")


# -----------------------------
# 7. Main pipeline
# -----------------------------
def main():
    # Load latest S3 file
    latest_file = get_latest_s3_file()
    df = load_csv_from_s3(latest_file)

    # Combine article content
    contents = df["content"].tolist()
    combined_text = "\n".join(contents)

    print("[INFO] Generating summary…")
    summary = generate_summary(combined_text)

    print("[INFO] Generating keywords…")
    keywords = generate_keywords(combined_text)

    print("[INFO] Generating insight…")
    insight = generate_insight(combined_text)

    # Save results into RDS
    save_daily_insight(summary, keywords, insight)
    save_articles(df)

    print("\n🎉 Completed!")
    print("Today's summary:", summary)
    print("Today's keywords:", keywords)
    print("Today's insight:", insight)


if __name__ == "__main__":
    main()
