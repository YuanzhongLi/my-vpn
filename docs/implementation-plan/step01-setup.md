# Step 1: 環境準備・Terraform基盤

## 目的

Terraformプロジェクトの初期セットアップを行い、`terraform init` が正常に完了する状態にする。

## 前提確認

- [x] AWS CLI プロファイル `my-vpn-terraform-prd` 動作確認済み
  - Account: `<AWS_ACCOUNT_ID>`
  - IAM User: `my-vpn-terraform-prd`
- [x] Terraform v1.14.4 インストール済み

## 作業内容

### 1. .gitignore 作成
WireGuard鍵、Terraform state、秘密情報を除外

### 2. Terraform バージョン固定
`.terraform-version` で v1.14.4 を固定

### 3. CloudFormation: S3バックエンド作成
`cloudformation/terraform-backend.yaml` で以下を作成:
- S3バケット: `my-vpn-terraform-prd` (tfstate保管、暗号化・バージョニング有効)
- DynamoDBテーブル: `my-vpn-terraform-lock-prd` (state lock)

### 4. Terraform 初期化
- `terraform/prd/versions.tf`: provider設定 (AWS, profile指定, default_tags)
- `terraform/prd/backend.tf`: S3バックエンド設定
- `terraform/prd/variables.tf`: locals (env, account_id, region)
- `terraform/prd/aws.tf`: 空のmodule呼び出しファイル（後続ステップで追加）

### 5. terraform init 実行・確認

## 作成ファイル一覧

| ファイル | 内容 |
|---------|------|
| `.gitignore` | 機密ファイル・Terraform state除外 |
| `terraform/.terraform-version` | Terraformバージョン固定 |
| `cloudformation/terraform-backend.yaml` | S3 + DynamoDB (CFnスタック) |
| `terraform/prd/versions.tf` | provider設定 |
| `terraform/prd/backend.tf` | S3バックエンド |
| `terraform/prd/variables.tf` | locals定義 |
| `terraform/prd/aws.tf` | module呼び出し（空） |

## 検証

- `aws cloudformation describe-stacks` でスタック作成確認
- `terraform init` が成功すること
- `terraform plan` がエラーなく実行できること（リソース0件）
