# AI Daily Insights: Cloud-Native NLP Automation Platform

## 📘 Overview

AI Daily Insights is an automated system designed to collect, analyze, and summarize daily AI-related news. It integrates AWS services, NLP processing, and a web interface to automatically crawl articles, perform analysis, store structured results, and deliver summaries, keywords, and insights in real time through a web dashboard.

## 🏛️ Architecture Summary

- **Crawling:** Automated daily execution using EventBridge and Lambda
- **Storage:** Raw data stored in S3; processed results stored in RDS (MySQL)
- **NLP Processing:** EC2-based analyzer running summarization, keyword extraction, and insight generation (OpenAI o3-mini)
- **Web Service:** Apache HTTP Server and FastAPI for UI and API integration
- **Security:** VPC with public/private subnet separation, IAM roles, OpenVPN
- **Global Distribution:** CloudFront and Route53 for low-latency global access
- **Monitoring:** CloudWatch logs and SNS notifications for pipeline status

**AI Daily Insights Deck:** `./presentation/final_presentation.pdf`

## 🧰 Technologies Used

### AWS

- EC2, Lambda, S3, RDS (MySQL)
- EventBridge, SSM Run Command
- CloudFront, Route53
- CloudWatch, SNS
- IAM, VPC (Public/Private Subnets)

### Backend

- Python, FastAPI
- OpenAI o3-mini (summarization and insight generation)

### Frontend

- Apache HTTP Server (PHP)

## 🔄 Pipeline Workflow

1. EventBridge triggers the Lambda crawler every morning at 9 AM.
2. The Lambda function retrieves AI-related news and stores the raw text in S3.
3. SSM Run Command activates the EC2 NLP analyzer.
4. EC2 processes:
    - One-line summary
    - Multi-sentence insight
    - Keyword extraction
5. Processed results are written to RDS.
6. The web server queries the database and updates the UI.
7. CloudWatch and SNS deliver completion logs and alerts.
8. CloudFront provides improved global performance.

## ⭐ Key Features

- Fully automated daily news processing
- Keyword, summary, and insight generation
- Scalable AWS-native architecture
- Secure internal operations with OpenVPN
- Real-time monitoring and alerting
- Global content delivery optimization

## 📈 Performance Observation

When simulating U.S.-based users:

- Direct ALB access averaged **2.05 seconds**
- CloudFront distribution reduced load time to **1.39 seconds**

## 🚀 Future Improvements

- Extend serverless adoption using API Gateway and ECS Fargate
- Provide customizable user-defined analysis pipelines
- Incorporate real-time trend processing using Kinesis Data Streams
