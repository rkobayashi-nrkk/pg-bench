# RDS PostgreSQL New Relic 負荷テストデモ環境構築ガイド
このドキュメントでは、AWS RDS PostgreSQL 環境に対して、New Relic で監視可能な様々なデータベース負荷パターンを意図的に発生させるためのデモ環境構築手順を説明します 。

## データベースの初期設定とテーブル作成
負荷テストを実行する前に、対象のAurora PostgreSQLデータベースに pgbench のテストデータと、カスタムスクリプトで使用する追加テーブルを作成します 。

### a. 環境変数の設定
EC2インスタンスのシェルで、PostgreSQLクライアントがDBに接続できるよう環境変数を設定します 。

YOUR_DB_ENDPOINTとYOUR_POSTGRES_PASSWORD は実際の値に置き換えてください 。

```Bash
export PGBENCH_HOST="YOUR_DB_ENDPOINT" # DBのエンドポイント
export PGBENCH_PORT="5432"
export PGBENCH_USER="postgres" # 接続ユーザー名
export PGBENCH_DBNAME="pgbench_test" # テスト用DB名(任意)
export PGBENCH_PASSWORD="YOUR_POSTGRES_PASSWORD" # *** 実際のパスワードに置き換えてください***
```

### b. テスト用データベースの作成

pgbench_test という名前のデータベースを作成します（既に存在する場合はスキップされます） 。

```Bash
PGPASSWORD=$PGBENCH_PASSWORD psql -h $PGBENCH_HOST -p $PGBENCH_PORT -U $PGBENCH_USER -c "CREATE DATABASE $PGBENCH_DBNAME"
```

### c. pgbench テストデータの初期化

pgbench のデフォルトテストデータをデータベースに初期化します 。
ß
`-s 1000` は約15GBのデータを生成します 。

```Bash
PGPASSWORD=$PGBENCH_PASSWORD pgbench -i -s 1000 -h $PGBENCH_HOST -p $PGBENCH_PORT -U $PGBENCH_USER -d $PGBENCH_DBNAME
```

### d. 追加テーブルとインデックスの作成、初期データ投入
カスタムスクリプトで使用する追加のテーブルとインデックスを作成し、初期データを投入します 。

```Bash
PGPASSWORD=$PGBENCH_PASSWORD psql -h $PGBENCH_HOST -p $PGBENCH_PORT -U $PGBENCH_USER -d $PGBENCH_DBNAME << EOF
-- products テーブル
CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    stock_quantity INT NOT NULL
);
CREATE INDEX idx_products_category ON products (category);

-- orders テーブル
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount NUMERIC(10, 2) NOT NULL,
    status VARCHAR(20) NOT NULL
);
CREATE INDEX idx_orders_customer_id ON orders (customer_id);

-- order_items テーブル
CREATE TABLE order_items (
    order_item_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES orders (order_id),
    product_id INT NOT NULL REFERENCES products (product_id),
    quantity INT NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL
);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);
CREATE INDEX idx_order_items_order_id ON order_items (order_id);

-- demo_log_events テーブル (大量INSERT/DELETE用)
CREATE TABLE demo_log_events (
    event_id BIGSERIAL PRIMARY KEY,
    event_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    event_type VARCHAR(50) NOT NULL,
    message TEXT,
    payload JSONB
);
CREATE INDEX idx_demo_log_events_event_time ON demo_log_events (event_time);
CREATE INDEX idx_demo_log_events_event_type ON demo_log_events (event_type);

-- deadlock_test テーブル (デッドロック用)
CREATE TABLE deadlock_test (
    id INT PRIMARY KEY,
    value INT
);

-- 初期データの投入
INSERT INTO products (product_name, category, price, stock_quantity)
SELECT
    'Product' || generate_series(1, 1000),
    CASE (random() * 5)::int
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Books'
        WHEN 2 THEN 'Clothing'
        WHEN 3 THEN 'Food'
        ELSE 'Home Goods'
    END,
    (random() * 1000 + 1)::numeric(10, 2),
    (random() * 10000 + 100)::int;

INSERT INTO orders (customer_id, order_date, total_amount, status)
SELECT
    (random() * 1000000)::int + 1,
    '2024-01-01'::timestamp + (random() * INTERVAL '1 year'),
    (random() * 5000 + 10)::numeric(10, 2),
    CASE (random() * 3)::int
        WHEN 0 THEN 'Completed'
        WHEN 1 THEN 'Pending'
        ELSE 'Shipped'
    END
FROM generate_series(1, 100000);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    (random() * 99999)::int + 1,
    (random() * 999)::int + 1,
    (random() * 10)::int + 1,
    (random() * 500 + 1)::numeric(10, 2)
FROM generate_series(1, 500000);

INSERT INTO deadlock_test (id, value) VALUES (1, 100);
INSERT INTO deadlock_test (id, value) VALUES (2, 200);

ANALYZE; -- 統計情報を更新
EOF
```

## 2. pgbench の実行準備

pgbench は PostgreSQL データベースのベンチマークツールですが、ここではカスタムスクリプトを使用して多様なワークロードをシミュレートしています 。

### カスタムSQLスクリプトの準備
pgbench が実行される EC2 インスタンスの `/home/ec2-user/scripts/` ディレクトリにスクリプトをダウンロードします

* frequent_select_completed.sql
* frequent_select_pending.sql
* frequent_select_shipped.sql
* heavy_reporting_select_electronics.sql
* heavy_reporting_select_books.sql
* heavy_reporting_select_clothing.sql
* heavy_reporting_select_food.sql
* heavy_reporting_select_home_goods.sql
* bulk_insert.sql
* bulk_delete.sql
* deadlock_script_a.sql
* deadlock_script_b.sql
* run_pgbench_load.sh

 ```bash
 mkdir /home/ec2-user/scripts/
 cd /home/ec2-user/scripts/
 git clone https://github.com/rkobayashi-nrkk/pg-bench.git
 ```

### 実行コマンドとパラメータ

run_pgbench_load.sh スクリプト内で、以下の pgbench コマンドが実行されます 。


```Bash
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
```

* -c 64: 64個のクライアントが同時にデータベースに接続し、トランザクションを実行します.
* -j 4: 4つのスレッドを使用してクライアントリクエストを処理します.
* -T 300: ベンチマークを **300秒（5分間）**実行します.
* -M prepared: プリペアドステートメントを使用します.
* -f <script_name>@<weight>: 複数のカスタムSQLスクリプトを指定し、それぞれの実行頻度を ウェイトで制御します.

#### 各SQLスクリプトの目的

* frequent_select_*.sql: **高頻度な参照系クエリ（SELECT文）**をシミュレートし、データベースの読み取り負荷の大部分を占めます 。
* heavy_reporting_select_*.sql: **リソースを多く消費する重い参照系クエリ（SELECT文）**をシミュレートし、CPUやI/Oに大きな負荷をかけます 。
* bulk_insert.sql: **大量の新規データ挿入（INSERT文）**をシミュレートし、ディスクI/Oとトランザクションログへの書き込み負荷を発生させます.
* bulk_delete.sql: **大量のデータ削除（DELETE文）**をシミュレートし、テーブルやインデックスへの影響を発生させます.
* deadlock_script_a.sql と deadlock_script_b.sql: デッドロックを意図的に発生させ、New Relic のダッシュボード上でデッドロックイベントやエラーが検知されることを確認します.

## 3. Cronの設定
負荷テストスクリプト run_pgbench_load.sh は、EC2 インスタンス上の Cron ジョブとして定期的に実行されるように設定されています 。

### スクリプトのパーミッション設定
作成したスクリプトファイルに実行権限を付与します 。

```Bash
chmod +x /home/ec2-user/scripts/run_pgbench_load.sh
```

### c. Cronジョブの登録

crontab -e コマンドを使用して、現在のユーザー（例：ec2-user）の Cron ジョブを編集し、以下の行を追加して保存します 。

```Bash
0 * * * * /home/ec2-user/scripts/run_pgbench_load.sh >> /var/log/pgbench_load/cron.log 2>&1
```

* 0 * * * *: **毎日、毎時0分（つまり毎正時）**にジョブを実行します 。
* >> /var/log/pgbench_load/cron.log 2>&1: スクリプトの標準出力と標準エラー出力を、指定されたログファイルに追記します 。

### Cron設定の目的
この設定により、デモ環境のAurora PostgreSQL データベースに対し、1時間ごとに自動的に pgbench による様々な負荷テストが5分間実行されます 。これにより、New Relic のダッシュボードで時間の経過とともに負荷メトリクス（CPU使用率、I/O、TPS、デッドロックなど）が定期的に上昇する様子を継続的にデモできます 。