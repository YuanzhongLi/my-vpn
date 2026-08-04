TERRAFORM_DIR := terraform/prd
AWS_PROFILE := my-vpn-terraform-prd
AWS_REGION := ap-northeast-1
AWS := aws --profile $(AWS_PROFILE) --region $(AWS_REGION)

INSTANCE_ID = $$(cd $(TERRAFORM_DIR) && terraform output -raw ec2_vpn_id)
ZONE_ID = $$(cd $(TERRAFORM_DIR) && terraform output -raw route53_vpn_zone_id)
SUBDOMAIN = $$(cd $(TERRAFORM_DIR) && terraform output -raw subdomain)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

init-backend: ## Deploy CloudFormation stack for Terraform S3 backend (first time only)
	aws cloudformation deploy \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--template-file cloudformation/terraform-backend.yaml \
		--stack-name my-vpn-terraform-backend

setup-config: ## Copy .envrc / terraform.tfvars from examples if not present yet
	@if [ -f $(TERRAFORM_DIR)/.envrc ]; then \
		echo "$(TERRAFORM_DIR)/.envrc already exists, skipping."; \
	else \
		cp $(TERRAFORM_DIR)/.envrc.example $(TERRAFORM_DIR)/.envrc && \
		echo "Created $(TERRAFORM_DIR)/.envrc - please edit AWS_PROFILE."; \
	fi
	@if [ -f $(TERRAFORM_DIR)/terraform.tfvars ]; then \
		echo "$(TERRAFORM_DIR)/terraform.tfvars already exists, skipping."; \
	else \
		cp $(TERRAFORM_DIR)/terraform.tfvars.example $(TERRAFORM_DIR)/terraform.tfvars && \
		echo "Created $(TERRAFORM_DIR)/terraform.tfvars - please edit subdomain."; \
	fi

tf-init: ## Initialize Terraform
	cd $(TERRAFORM_DIR) && terraform init

tf-apply: ## Apply Terraform (create VPC/EC2/SecurityGroup/Route53 etc.)
	cd $(TERRAFORM_DIR) && terraform apply

start-vpn: ## Start VPN (EC2 + EIP + DNS)
	@INSTANCE_ID=$(INSTANCE_ID) && \
	ZONE_ID=$(ZONE_ID) && \
	SUBDOMAIN=$(SUBDOMAIN) && \
	STATE=$$($(AWS) ec2 describe-instances --instance-ids $$INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text) && \
	if [ "$$STATE" != "running" ]; then \
		echo "Starting EC2 $$INSTANCE_ID ..." && \
		$(AWS) ec2 start-instances --instance-ids $$INSTANCE_ID > /dev/null && \
		echo "Waiting for instance to be running ..." && \
		$(AWS) ec2 wait instance-running --instance-ids $$INSTANCE_ID; \
	else \
		echo "EC2 $$INSTANCE_ID is already running."; \
	fi && \
	echo "Allocating EIP ..." && \
	ALLOC_ID=$$($(AWS) ec2 allocate-address --query 'AllocationId' --output text) && \
	EIP=$$($(AWS) ec2 describe-addresses --allocation-ids $$ALLOC_ID --query 'Addresses[0].PublicIp' --output text) && \
	echo "EIP allocated: $$EIP ($$ALLOC_ID)" && \
	echo "Associating EIP to EC2 ..." && \
	$(AWS) ec2 associate-address --instance-id $$INSTANCE_ID --allocation-id $$ALLOC_ID > /dev/null && \
	echo "Updating DNS $$SUBDOMAIN -> $$EIP ..." && \
	$(AWS) route53 change-resource-record-sets --hosted-zone-id $$ZONE_ID --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"'"$$SUBDOMAIN"'","Type":"A","TTL":60,"ResourceRecords":[{"Value":"'"$$EIP"'"}]}}]}' > /dev/null && \
	echo "" && \
	echo "VPN started successfully!" && \
	echo "  Instance: $$INSTANCE_ID" && \
	echo "  EIP:      $$EIP" && \
	echo "  Domain:   $$SUBDOMAIN"

stop-vpn: ## Stop VPN (EIP release + EC2 stop)
	@INSTANCE_ID=$(INSTANCE_ID) && \
	ALLOC_ID=$$($(AWS) ec2 describe-addresses --filters "Name=instance-id,Values=$$INSTANCE_ID" --query 'Addresses[0].AllocationId' --output text 2>/dev/null) && \
	if [ "$$ALLOC_ID" != "None" ] && [ -n "$$ALLOC_ID" ]; then \
		ASSOC_ID=$$($(AWS) ec2 describe-addresses --allocation-ids $$ALLOC_ID --query 'Addresses[0].AssociationId' --output text) && \
		echo "Disassociating EIP ..." && \
		$(AWS) ec2 disassociate-address --association-id $$ASSOC_ID && \
		echo "Releasing EIP $$ALLOC_ID ..." && \
		$(AWS) ec2 release-address --allocation-id $$ALLOC_ID; \
	else \
		echo "No EIP attached."; \
	fi && \
	STATE=$$($(AWS) ec2 describe-instances --instance-ids $$INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text) && \
	if [ "$$STATE" = "stopped" ]; then \
		echo "EC2 $$INSTANCE_ID is already stopped."; \
	else \
		echo "Stopping EC2 $$INSTANCE_ID ..." && \
		$(AWS) ec2 stop-instances --instance-ids $$INSTANCE_ID > /dev/null && \
		echo "Waiting for instance to stop ..." && \
		$(AWS) ec2 wait instance-stopped --instance-ids $$INSTANCE_ID && \
		echo "EC2 $$INSTANCE_ID is now stopped."; \
	fi && \
	echo "" && \
	echo "VPN stopped."

status-vpn: ## Show VPN status (EC2 + EIP + DNS)
	@INSTANCE_ID=$(INSTANCE_ID) && \
	SUBDOMAIN=$(SUBDOMAIN) && \
	echo "=== EC2 ===" && \
	$(AWS) ec2 describe-instances --instance-ids $$INSTANCE_ID \
		--query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,InstanceType:InstanceType}' \
		--output table && \
	echo "" && \
	echo "=== EIP ===" && \
	EIP_INFO=$$($(AWS) ec2 describe-addresses --filters "Name=instance-id,Values=$$INSTANCE_ID" --query 'Addresses[0].{PublicIp:PublicIp,AllocationId:AllocationId}' --output text 2>/dev/null) && \
	if [ "$$EIP_INFO" = "None	None" ] || [ -z "$$EIP_INFO" ]; then \
		echo "  No EIP attached."; \
	else \
		echo "  $$EIP_INFO"; \
	fi && \
	echo "" && \
	echo "=== DNS ===" && \
	echo "  $$SUBDOMAIN -> $$(dig +short A $$SUBDOMAIN 2>/dev/null || echo 'N/A')"

ssm-vpn: ## Connect to VPN instance via SSM Session Manager
	@INSTANCE_ID=$(INSTANCE_ID) && \
	echo "Connecting to $$INSTANCE_ID ..." && \
	$(AWS) ssm start-session --target $$INSTANCE_ID

dns-ns-show: ## Show Route53 NS records for DNS delegation
	@cd $(TERRAFORM_DIR) && terraform output -json route53_vpn_name_servers | jq -r '.[]'

add-client: ## Add a WireGuard client peer and print its config + QR code (usage: make add-client NAME=client1 IP=10.0.0.2)
	@NAME=$${NAME:-client1} && \
	IP=$${IP:-10.0.0.2} && \
	INSTANCE_ID=$(INSTANCE_ID) && \
	SUBDOMAIN=$(SUBDOMAIN) && \
	SCRIPT="set -euo pipefail; cd /etc/wireguard; command -v qrencode >/dev/null 2>&1 || dnf install -y qrencode >/dev/null; umask 077; wg genkey | tee $${NAME}_private.key | wg pubkey > $${NAME}_public.key; wg set wg0 peer \$$(cat $${NAME}_public.key) allowed-ips $${IP}/32; wg-quick save wg0; printf '[Interface]\nPrivateKey = %s\nAddress = $${IP}/32\nDNS = 1.1.1.1, 1.0.0.1\n\n[Peer]\nPublicKey = %s\nEndpoint = $${SUBDOMAIN}:51820\nAllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25\n' \"\$$(cat $${NAME}_private.key)\" \"\$$(cat server_public.key)\" > $${NAME}.conf; echo '--- QR CODE ---'; qrencode -t ansiutf8 < $${NAME}.conf; echo '--- CONF ---'; cat $${NAME}.conf; rm -f $${NAME}_private.key $${NAME}.conf" && \
	CMD_ID=$$($(AWS) ssm send-command --cli-input-json "$$(jq -n --arg id "$$INSTANCE_ID" --arg s "$$SCRIPT" '{InstanceIds:[$$id], DocumentName:"AWS-RunShellScript", Parameters:{commands:[$$s]}}')" --query 'Command.CommandId' --output text) && \
	echo "Running on $$INSTANCE_ID (command $$CMD_ID) ..." && \
	while STATUS=$$($(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'Status' --output text 2>/dev/null); [ "$$STATUS" = "InProgress" ] || [ "$$STATUS" = "Pending" ]; do sleep 2; done && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardOutputContent' --output text && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardErrorContent' --output text

list-clients: ## List registered WireGuard client peers (name + public key + handshake status)
	@INSTANCE_ID=$(INSTANCE_ID) && \
	SCRIPT="set -euo pipefail; cd /etc/wireguard; echo '=== Registered clients ==='; found=0; for f in *_public.key; do [ -e \"\$$f\" ] || continue; [ \"\$$f\" = server_public.key ] && continue; found=1; echo \"\$${f%_public.key}: \$$(cat \$$f)\"; done; [ \"\$$found\" = 1 ] || echo '(none)'; echo; echo '=== wg show wg0 ==='; wg show wg0" && \
	CMD_ID=$$($(AWS) ssm send-command --cli-input-json "$$(jq -n --arg id "$$INSTANCE_ID" --arg s "$$SCRIPT" '{InstanceIds:[$$id], DocumentName:"AWS-RunShellScript", Parameters:{commands:[$$s]}}')" --query 'Command.CommandId' --output text) && \
	while STATUS=$$($(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'Status' --output text 2>/dev/null); [ "$$STATUS" = "InProgress" ] || [ "$$STATUS" = "Pending" ]; do sleep 2; done && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardOutputContent' --output text && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardErrorContent' --output text

remove-client: ## Remove a registered WireGuard client peer (usage: make remove-client NAME=client1)
	@if [ -z "$(NAME)" ]; then echo "Usage: make remove-client NAME=<client-name>"; exit 1; fi
	@NAME=$(NAME) && \
	INSTANCE_ID=$(INSTANCE_ID) && \
	SCRIPT="set -euo pipefail; cd /etc/wireguard; if [ ! -f $${NAME}_public.key ]; then echo \"No such client: $${NAME}\" >&2; exit 1; fi; PUB=\$$(cat $${NAME}_public.key); wg set wg0 peer \$$PUB remove; wg-quick save wg0; rm -f $${NAME}_public.key; echo \"Removed client $${NAME} (pubkey \$$PUB)\"" && \
	CMD_ID=$$($(AWS) ssm send-command --cli-input-json "$$(jq -n --arg id "$$INSTANCE_ID" --arg s "$$SCRIPT" '{InstanceIds:[$$id], DocumentName:"AWS-RunShellScript", Parameters:{commands:[$$s]}}')" --query 'Command.CommandId' --output text) && \
	while STATUS=$$($(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'Status' --output text 2>/dev/null); [ "$$STATUS" = "InProgress" ] || [ "$$STATUS" = "Pending" ]; do sleep 2; done && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardOutputContent' --output text && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardErrorContent' --output text

setup-monitoring: ## (Re-)install the wg-monitor timer on the running EC2 without a full terraform apply
	@INSTANCE_ID=$(INSTANCE_ID) && \
	CMD_ID=$$($(AWS) ssm send-command --cli-input-json "$$(jq -n --arg id "$$INSTANCE_ID" --rawfile s scripts/wg-monitor-setup.sh '{InstanceIds:[$$id], DocumentName:"AWS-RunShellScript", Parameters:{commands:[$$s]}}')" --query 'Command.CommandId' --output text) && \
	while STATUS=$$($(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'Status' --output text 2>/dev/null); [ "$$STATUS" = "InProgress" ] || [ "$$STATUS" = "Pending" ]; do sleep 2; done && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardOutputContent' --output text && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardErrorContent' --output text

tail-logs: ## Tail the wg-monitor log in real time (Ctrl+C to stop)
	@INSTANCE_ID=$(INSTANCE_ID) && \
	echo "Tailing wg-monitor.log on $$INSTANCE_ID (Ctrl+C to stop) ..." && \
	$(AWS) ssm start-session --target $$INSTANCE_ID \
		--document-name AWS-StartInteractiveCommand \
		--parameters command="sudo tail -f /var/log/wg-monitor.log"

fetch-logs: ## Download wg-monitor.log (and rotated archives) to ./logs/<timestamp>/
	@INSTANCE_ID=$(INSTANCE_ID) && \
	OUTDIR=logs/$$(date -u +%Y%m%dT%H%M%SZ) && \
	mkdir -p $$OUTDIR && \
	SCRIPT="cd /var/log; { cat wg-monitor.log 2>/dev/null; for f in \$$(ls -1 wg-monitor.log.*.gz 2>/dev/null | sort); do zcat \$$f; done; } | base64 -w0" && \
	CMD_ID=$$($(AWS) ssm send-command --cli-input-json "$$(jq -n --arg id "$$INSTANCE_ID" --arg s "$$SCRIPT" '{InstanceIds:[$$id], DocumentName:"AWS-RunShellScript", Parameters:{commands:[$$s]}}')" --query 'Command.CommandId' --output text) && \
	while STATUS=$$($(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'Status' --output text 2>/dev/null); [ "$$STATUS" = "InProgress" ] || [ "$$STATUS" = "Pending" ]; do sleep 2; done && \
	$(AWS) ssm get-command-invocation --command-id $$CMD_ID --instance-id $$INSTANCE_ID --query 'StandardOutputContent' --output text | base64 -d > $$OUTDIR/wg-monitor.log && \
	echo "Saved to $$OUTDIR/wg-monitor.log ($$(wc -l < $$OUTDIR/wg-monitor.log) lines)"

.PHONY: help init-backend setup-config tf-init tf-apply start-vpn stop-vpn status-vpn ssm-vpn dns-ns-show add-client list-clients remove-client setup-monitoring tail-logs fetch-logs
