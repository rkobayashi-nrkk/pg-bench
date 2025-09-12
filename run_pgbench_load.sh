#!/bin/bash

# スクリプトの実行ディレクトリに移動
cd "$(dirname "$0")"

# ログファイルのパスを定義
LOG_DIR="/var/log/pgbench_load"
LOG_FILE="${LOG_DIR}/pgbench_$(date +\%Y\%m\%d_\%H\%M\%S).log"
ERROR_LOG="${LOG_DIR}/pgbench_error.log"

# ログディレクトリが存在しない場合は作成
mkdir -p "$LOG_DIR"

# DB接続情報
PGBENCH_HOST="YOUR_DB_ENDPOINT" # DBのエンドポイント
PGBENCH_PORT="5432"
PGBENCH_USER="postgres" # 接続ユーザー名
PGBENCH_DBNAME="pgbench_test" # テスト用DB名
PGBENCH_PASSWORD="YOUR_POSTGRES_PASSWORD" # ★★★ 実際のパスワードに置き換えてください ***

# pgbenchコマンドの実行
PGPASSWORD="$PGBENCH_PASSWORD" \
PGHOST="$PGBENCH_HOST" PGPORT="$PGBENCH_PORT" PGUSER="$PGBENCH_USER" PGDATABASE="$PGBENCH_DBNAME" \
pgbench -c 64 -j 4 -T 300 -M prepared \
-f frequent_select_completed.sql@6 \
-f frequent_select_pending.sql@6 \
-f frequent_select_shipped.sql@6 \
-f heavy_reporting_select_electronics.sql@1 \
-f heavy_reporting_select_books.sql@1 \
-f heavy_reporting_select_clothing.sql@1 \
-f heavy_reporting_select_food.sql@1 \
-f heavy_reporting_select_home_goods.sql@1 \
-f bulk_insert.sql@2 \
-f bulk_delete.sql@1 \
-f deadlock_script_a.sql@1 \
-f deadlock_script_b.sql@1 \
> "$LOG_FILE" 2>> "$ERROR_LOG"

# エラーチェック (オプション)
if [ $? -ne 0 ]; then
  echo "$(date): pgbench command failed. Check ${ERROR_LOG} for details." >> "$ERROR_LOG"
fi

# 古いログファイルのクリーンアップ (例: 7日以上前のログを削除)
find "$LOG_DIR" -type f -name "pgbench_*.log" -mtime +7 -delete
echo "$(date): pgbench load test completed." >> "$ERROR_LOG" # 実行完了ログ