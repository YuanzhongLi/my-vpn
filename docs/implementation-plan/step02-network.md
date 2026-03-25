# Step 2: VPC・ネットワーク構築

## 目的

VPNサーバーを配置するVPCとネットワークリソースをTerraformで構築する。

## 参考プロジェクトから踏襲するパターン

- モジュール分割: vpc, subnet, internet_gateway, route_table を個別モジュール化
- 値はモジュール内でハードコード、env変数で環境識別
- output経由でモジュール間連携
- 命名規則: `my-vpn-{resource}-{detail}-${var.env}`

## 本プロジェクトとの差異

- **シンプル構成**: Public Subnet 1つのみ（Private不要）
- **AZ**: 1a のみ（HA不要、コスト最小化）
- **NACL**: カスタムルール設定（セキュリティ設計に基づく）

## 作成するモジュール・ファイル

### 1. modules/aws/vpc/
- VPC (10.1.0.0/16)
- DNS Support / DNS Hostnames 有効

### 2. modules/aws/subnet/
- Public Subnet (10.1.1.0/24, ap-northeast-1a)
- map_public_ip_on_launch = true

### 3. modules/aws/internet_gateway/
- IGW作成、VPCにアタッチ

### 4. modules/aws/route_table/
- Public Route Table (0.0.0.0/0 → IGW)
- サブネット関連付け

### 5. modules/aws/nacl/
- Inbound: UDP 51820 (WireGuard), TCP 22 (SSH), エフェメラルポート
- Outbound: All
- サブネット関連付け

### 6. prd/aws.tf にmodule呼び出し追加

## 検証

- `terraform plan` でリソース数確認
- `terraform apply` 実行
- AWSコンソールでVPC、Subnet、IGW、Route Table、NACLを目視確認
