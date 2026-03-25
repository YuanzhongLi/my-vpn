# iPhoneクライアント設定ガイド

## 概要

iPhoneからWireGuard VPNサーバーに接続するための設定手順を説明する。
主にWireGuard公式アプリを使用する方法と、参考としてIKEv2/IPSecのiOS標準設定も記載する。

## 前提

- VPNサーバーが構築済みで起動していること
- サーバーの公開鍵、Elastic IP、WireGuardポートが確定していること
- クライアント用の鍵ペアが生成済みであること

## 方法1: WireGuard公式アプリ（推奨）

### Step 1: アプリのインストール

1. App Storeで「WireGuard」を検索
2. WireGuard公式アプリ（無料）をインストール

### Step 2: クライアント設定ファイルの作成

サーバー側でクライアント用の設定ファイルを生成する。

```ini
# client.conf
[Interface]
PrivateKey = <client_private_key>
Address = 10.0.0.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = <server_public_key>
# PresharedKey = <preshared_key>   # オプション
Endpoint = <server_elastic_ip>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

#### パラメータ説明

| パラメータ | 説明 |
|-----------|------|
| PrivateKey | クライアントの秘密鍵 |
| Address | VPNトンネル内でのクライアントIP |
| DNS | VPN接続時に使用するDNSサーバー |
| PublicKey | サーバーの公開鍵 |
| PresharedKey | 追加の暗号化レイヤー（オプション） |
| Endpoint | サーバーのElastic IP:ポート |
| AllowedIPs | VPN経由にするトラフィック（0.0.0.0/0 = 全通信） |
| PersistentKeepalive | NAT越え用のKeepAlive間隔（秒） |

### Step 3: QRコードでの設定インポート（最も簡単）

サーバー側でQRコードを生成：

```bash
# qrencodeのインストール
sudo dnf install qrencode  # Amazon Linux 2023
# or
sudo apt install qrencode  # Ubuntu

# QRコード生成
qrencode -t ansiutf8 < client.conf
```

iPhoneでの操作：
1. WireGuardアプリを開く
2. 「+」ボタンをタップ
3. 「QRコードから作成」を選択
4. カメラでQRコードをスキャン
5. トンネル名を入力（例: "Japan VPN"）
6. 「保存」をタップ

### Step 4: 設定ファイルでのインポート（代替方法）

1. `client.conf` をiPhoneに転送（AirDrop、メール添付等）
2. WireGuardアプリを開く
3. 「+」ボタンをタップ
4. 「ファイル、アーカイブから作成」を選択
5. confファイルを選択

### Step 5: On-Demand設定（自動接続）

VPN接続の自動化設定：

1. WireGuardアプリでトンネルを選択
2. 「編集」をタップ
3. 「On-Demand有効化」セクション:

| 設定 | 推奨値 | 説明 |
|------|--------|------|
| Wi-Fi | 常にON | Wi-Fi接続時は常にVPN |
| Cellular | 常にON | モバイル通信時も常にVPN |
| 特定SSIDを除外 | 自宅Wi-Fi等 | 信頼できるネットワークでは無効化 |

### Step 6: 接続

1. WireGuardアプリでトンネルのスイッチをON
2. またはiOS設定 > VPN からワンタップで切り替え
3. ステータスバーに「VPN」アイコンが表示されれば接続成功

## 方法2: IKEv2/IPSec（iOS標準機能）

### 注意

この方法はサーバー側でstrongSwanの追加構築が必要。WireGuardが推奨だが、WireGuardアプリがインストールできない場合のフォールバックとして記載する。

### Step 1: iOS設定画面からの設定

1. 設定 > 一般 > VPNとデバイス管理 > VPN
2. 「VPN構成を追加」をタップ
3. 以下を入力:

| 項目 | 値 |
|------|-----|
| タイプ | IKEv2 |
| 説明 | Japan VPN |
| サーバ | <server_elastic_ip> |
| リモートID | <server_domain_or_ip> |
| ローカルID | (空白) |
| ユーザ認証 | ユーザ名 |
| ユーザ名 | <vpn_username> |
| パスワード | <vpn_password> |

4. 「完了」をタップ

### Step 2: .mobileconfigプロファイル（代替方法）

Apple Configuratorまたは手動でプロファイルを作成し、配布する方法もある。
複数ユーザーへの展開時に有効。

## 接続テスト

### 基本テスト

VPN接続後に以下を確認：

| テスト | 方法 | 期待結果 |
|-------|------|---------|
| IPアドレス確認 | Safariで `ifconfig.me` にアクセス | サーバーのElastic IPが表示 |
| 日本IP確認 | Safariで `whatismyipaddress.com` にアクセス | 所在地が「Japan, Tokyo」 |
| DNSリーク | Safariで `dnsleaktest.com` にアクセス | DNSサーバーが指定のものだけ |
| 速度テスト | Safariで `fast.com` にアクセス | 許容可能な速度が出ている |
| 日本サイト | 日本限定サービスにアクセス | 正常にアクセス可能 |

### トラブルシューティング

| 症状 | 確認事項 | 対処 |
|------|---------|------|
| 接続できない | サーバーが起動しているか | `aws ec2 describe-instances` で確認 |
| 接続できない | セキュリティグループでUDP 51820が開いているか | AWSコンソールで確認 |
| 接続できない | サーバーのWireGuardが動作しているか | SSH接続して `wg show` |
| 接続は成功するが通信できない | IPフォワーディングが有効か | `sysctl net.ipv4.ip_forward` |
| 接続は成功するが通信できない | NAT設定(MASQUERADE)が正しいか | `iptables -t nat -L` |
| 速度が遅い | サーバーのCPU/ネットワーク使用率 | CloudWatchで確認 |
| DNSが解決しない | DNS設定が正しいか | クライアント設定のDNS項目を確認 |

## 複数デバイスの管理

### 1ユーザー = 1鍵ペア + 1IP

各デバイスに個別の鍵ペアとIPを割り当てる：

| デバイス | VPN IP | 設定名 |
|---------|--------|--------|
| iPhone (メイン) | 10.0.0.2 | Japan VPN - iPhone |
| iPad | 10.0.0.3 | Japan VPN - iPad |
| MacBook | 10.0.0.4 | Japan VPN - Mac |

サーバー側では各デバイスを個別の[Peer]として登録する。
