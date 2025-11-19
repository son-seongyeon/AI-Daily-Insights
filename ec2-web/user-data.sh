#!/bin/bash

# Update packages and install Apache + PHP
yum update -y
yum install -y httpd php php-cli php-common php-curl php-mysqlnd

# Enable and start Apache
systemctl enable httpd
systemctl start httpd

# APP API URL (provide via environment variable before running this script)
# export APP_ALB_DNS="your-app-alb-dns"
echo "APP_API_URL=http://${APP_ALB_DNS}/health" >> /etc/environment
echo "SetEnv APP_API_URL http://${APP_ALB_DNS}/health" >> /etc/httpd/conf/httpd.conf

# Remove default Apache index files
rm -f /var/www/html/index.*

# Write dashboard PHP file
tee /var/www/html/index.php > /dev/null << 'EOF'
<?php
// -----------------------------------------
// RDS MySQL connection info
// -----------------------------------------
$host = "my-db.cx28scimshga.ap-northeast-2.rds.amazonaws.com";
$user = "admin";
$pass = "password";
$db   = "insightdb";

// -----------------------------------------
// Connect to DB
// -----------------------------------------
try {
    $pdo = new PDO("mysql:host=$host;dbname=$db;charset=utf8mb4", $user, $pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("❌ DB connection failed: " . $e->getMessage());
}

// -----------------------------------------
// Fetch latest Insight
// -----------------------------------------
$insightQuery = $pdo->query("SELECT * FROM insights ORDER BY created_at DESC LIMIT 1");
$insight = $insightQuery->fetch(PDO::FETCH_ASSOC);

// -----------------------------------------
// Fetch article list
// -----------------------------------------
$articleQuery = $pdo->query("SELECT * FROM articles ORDER BY id DESC");
$articles = $articleQuery->fetchAll(PDO::FETCH_ASSOC);

// Today's date
$today = date("F d, Y");
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>AI Daily Insights Dashboard</title>
    <style>
        body {
            font-family: 'Noto Sans KR', sans-serif;
            line-height: 1.7;
            padding: 2.5rem;
            background: #f8fafc;
            color: #1e293b;
        }
        h1, h2 { margin-bottom: 1rem; }
        h1 { font-size: 2rem; color: #0f172a; font-weight: 700; }
        h2 { color: #334155; font-size: 1.3rem; margin-top: 2rem; }

        .date-box {
            font-size: 1.1rem;
            color: #475569;
            margin-bottom: 1rem;
        }

        .card {
            background: white;
            padding: 1.5rem;
            border-radius: 12px;
            box-shadow: 0 3px 10px rgba(0,0,0,0.05);
            margin-bottom: 1.5rem;
        }

        .tag {
            display: inline-block;
            background: #e2e8f0;
            color: #1e293b;
            padding: 6px 12px;
            border-radius: 6px;
            margin-right: 8px;
            margin-bottom: 6px;
            font-size: 0.9rem;
        }

        .news-list {
            border-left: 3px solid #3b82f6;
            padding-left: 14px;
            margin-top: 1rem;
            display: flex;
            flex-direction: column;
            gap: 18px;
        }

        .news-item { padding: 6px 0; }

        .news-title {
            font-size: 1.05rem;
            font-weight: 600;
            color: #0f172a;
            display: block;
            margin-bottom: 4px;
        }

        .news-link {
            font-size: 0.85rem;
            color: #2563eb;
            text-decoration: none;
        }

        .news-link:hover { text-decoration: underline; }
    </style>
</head>
<body>

    <!-- Date -->
    <div class="date-box">📅 <strong><?= $today ?></strong></div>

    <!-- Title -->
    <h1>🤖 <strong>AI Daily Insight</strong></h1>

    <?php if ($insight): ?>

        <!-- One-line Summary -->
        <h2>✨ One-line Summary</h2>
        <div class="card">
            <?= nl2br(htmlspecialchars($insight["summary"])) ?>
        </div>

        <!-- Keywords -->
        <h2>🏷 Today's Keywords</h2>
        <div class="card">
            <?php
            $keywords = explode(",", $insight["keywords"]);
            foreach ($keywords as $kw): ?>
                <span class="tag"><?= htmlspecialchars(trim($kw)) ?></span>
            <?php endforeach; ?>
        </div>

        <!-- Insight Paragraph -->
        <h2>🧠 Detailed Insight of the Day</h2>
        <div class="card">
            <?= nl2br(htmlspecialchars($insight["insight"])) ?>
            <div style="margin-top:0.5rem; font-size:0.85rem; color:#64748b;">
                Generated At: <?= $insight["created_at"] ?>
            </div>
        </div>

    <?php else: ?>
        <p>❌ No insights available.</p>
    <?php endif; ?>

    <!-- Article List -->
    <h2>📰 Today's Insight is Based on the Following Articles</h2>

    <div class="news-list">
        <?php foreach ($articles as $a): ?>
            <div class="news-item">
                <div class="news-title">📘 <?= htmlspecialchars($a["title"]) ?></div>
                <a class="news-link" href="<?= htmlspecialchars($a["link"]) ?>" target="_blank">
                    👉 Open Link
                </a>
            </div>
        <?php endforeach; ?>

        <?php if (empty($articles)): ?>
            <p>❌ No articles found.</p>
        <?php endif; ?>
    </div>

</body>
</html>
EOF

# Restart Apache to apply changes
systemctl restart httpd
