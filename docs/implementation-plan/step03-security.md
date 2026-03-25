# Step 3: セキュリティグループ・IAM

## 目的

VPNサーバー用のセキュリティグループとEC2用IAMロールをTerraformで構築する。

## 設計方針

- **NACL**: デフォルト（全許可）のまま使用。将来的にブラックリスト（特定IP拒否）用途で追加
- **Security Group**: ホワイトリスト方式で必要なポートのみ許可

## 作成するモジュール・ファイル

### 1. modules/aws/security_group/

VPNサーバー用セキュリティグループ:

#### Inbound
| プロトコル | ポート | ソース | 説明 |
|----------|-------|--------|------|
| UDP | 51820 | 0.0.0.0/0 | WireGuard |
| TCP | 22 | 0.0.0.0/0 | SSH（将来的に管理者IPに制限） |

#### Outbound
| プロトコル | ポート | 宛先 | 説明 |
|----------|-------|------|------|
| All | All | 0.0.0.0/0 | VPNクライアントの通信転送 |

> SSH を 0.0.0.0/0 にしている理由: 海外から接続するため固定IPを持たない。OS側のSSH強化（鍵認証のみ等）で補完する。

### 2. modules/aws/iam_role/

EC2用IAMロール + インスタンスプロファイル:

#### 信頼ポリシー
- EC2サービスからのAssumeRole

#### 権限ポリシー
- SSM Parameter Store: `/vpn/*` パラメータの読み取り
- CloudWatch Logs: ロググループ作成、ログ書き込み

### 3. prd/aws.tf にmodule呼び出し追加

## 検証

- `terraform plan` でリソース数確認
- `terraform apply` 実行
- AWSコンソールでSG、IAMロールを目視確認
