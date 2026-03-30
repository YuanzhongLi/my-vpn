# Step 5: Route53サブドメイン・DNS委譲

## 目的

VPNアカウント側でサブドメインのRoute53ホストゾーンを作成し、親アカウントからDNS委譲を設定する。

## 作成するモジュール・ファイル

### 1. modules/aws/route53/

- サブドメインのホストゾーン作成
- NSレコードとホストゾーンIDを出力

### 2. prd/variables.tf にサブドメイン変数追加

### 3. prd/aws.tf にmodule呼び出し追加

### 4. prd/outputs.tf にNSレコード出力追加

### 5. Makefile に dns-ns-show コマンド追加

## 親アカウントでのNS委譲手順（手動）

1. `make dns-ns-show` でNSレコード4つを確認
2. 親アカウント（`<親アカウントのプロファイル名>`）のRoute53コンソールを開く
3. 親ドメインのホストゾーンにNSレコードを追加:
   - レコード名: サブドメイン名
   - レコードタイプ: NS
   - 値: 表示された4つのネームサーバー
   - TTL: 300

## 設計判断

- **Aレコード**: Terraform管理外（Step 6でEIPと連動して動的更新）
- **NS委譲**: 親アカウントのRoute53コンソールで手動設定（1回限りの操作）
- **サブドメイン名**: locals変数化（ドキュメントでは伏せる）

## 検証

- `terraform plan` でリソース数確認
- `terraform apply` 実行
- `make dns-ns-show` でNS確認
- 親アカウントでNS委譲設定後、`dig NS <subdomain>` で確認
