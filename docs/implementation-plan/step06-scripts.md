# Step 6: 運用スクリプト（起動/停止/EIP管理）

## 目的

既存のMakefileコマンドにEIP管理とDNS更新を統合し、VPNの起動/停止を1コマンドで完結させる。

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `make start-vpn` | EC2起動 → EIP作成・アタッチ → DNS Aレコード更新 |
| `make stop-vpn` | EIP解放 → EC2停止 |
| `make status-vpn` | EC2状態 + EIP + DNS情報表示 |
| `make ssm-vpn` | SSM Session Manager接続 |

## 起動フロー (start-vpn)

1. EC2起動（起動済みならスキップ）
2. running になるまで待機
3. EIP作成 (allocate-address)
4. EIPをEC2にアタッチ (associate-address)
5. Route53 Aレコード更新 (UPSERT, TTL=60)
6. 最終状態表示

## 停止フロー (stop-vpn)

1. EC2にアタッチされたEIPを検索
2. EIPデタッチ + 解放（EIPがなければスキップ）
3. EC2停止（停止済みならスキップ）

## 設計判断

- **EIP**: Terraform管理外。AWS CLIで都度作成/削除
- **DNS TTL**: 60秒（IP変更の素早い反映）
- **IAM**: ローカルのAWSプロファイル権限で操作（EC2のIAMロール変更不要）

## 検証

1. `make stop-vpn` → EC2停止、EIP解放
2. `make start-vpn` → EC2起動、EIP作成、DNS更新
3. `make status-vpn` → 状態確認
4. `dig A vpn.example.com` → EIPのIPが返ること
5. `make stop-vpn` → EIP解放、EC2停止
