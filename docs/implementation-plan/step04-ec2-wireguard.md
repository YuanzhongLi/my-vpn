# Step 4: EC2インスタンス・WireGuard構築

## 目的

VPNサーバー用のEC2インスタンスを作成し、User DataでWireGuardを自動セットアップする。

## 作成するモジュール・ファイル

### 1. modules/aws/ec2/

| 項目 | 値 |
|------|-----|
| インスタンスタイプ | t3.nano (2 vCPU, 0.5GB RAM) |
| AMI | Amazon Linux 2023（SSM Parameterで最新を動的取得） |
| ストレージ | gp3 8GB |
| Key Pair | なし（SSM Session Managerで管理） |
| User Data | WireGuardインストール・初期設定スクリプト |

### 2. User Data スクリプト (user_data.sh)

1. パッケージ更新 + WireGuardインストール
2. IPフォワーディング有効化
3. WireGuardサーバー鍵生成
4. WireGuard設定ファイル生成（10.0.0.1/24, ポート51820）
5. iptables NAT設定（PostUp/PostDown）
6. WireGuardサービス起動 + 自動起動有効化

### 3. prd/aws.tf にmodule呼び出し追加

## 設計判断

- **EIPはTerraform管理外**: Step 6のスクリプトで都度作成/削除
- **鍵はUser Data内で生成**: 初回セットアップの簡易化
- **Key Pairなし**: SSM Session Manager or 一時EIPでSSH

## 検証

- `terraform plan` でリソース数確認
- `terraform apply` 実行
- `make status-vpn-instance` でEC2がrunning状態を確認
- `make ssm-vpn-instance` でSSM Session Manager接続後、以下を確認:

```bash
# WireGuardの起動確認
sudo wg show
# → interface: wg0, public key, listening port: 51820 が表示されること

# IPフォワーディングの確認
sysctl net.ipv4.ip_forward
# → net.ipv4.ip_forward = 1

# WireGuard自動起動の確認
sudo systemctl is-enabled wg-quick@wg0
# → enabled

# iptablesルールの確認
sudo iptables -t nat -L POSTROUTING -n
# → MASQUERADE が ens5 に設定されていること
```
