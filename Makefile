TERRAFORM_DIR := terraform/prd
AWS_PROFILE := my-vpn-terraform-prd
AWS_REGION := ap-northeast-1
AWS := aws --profile $(AWS_PROFILE) --region $(AWS_REGION)

INSTANCE_ID = $$(cd $(TERRAFORM_DIR) && terraform output -raw ec2_vpn_id)
ZONE_ID = $$(cd $(TERRAFORM_DIR) && terraform output -raw route53_vpn_zone_id)
SUBDOMAIN = $$(cd $(TERRAFORM_DIR) && terraform output -raw subdomain)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

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

.PHONY: help start-vpn stop-vpn status-vpn ssm-vpn dns-ns-show
