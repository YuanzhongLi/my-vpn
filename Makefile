TERRAFORM_DIR := terraform/prd
AWS_PROFILE := my-vpn-terraform-prd
AWS_REGION := ap-northeast-1

INSTANCE_ID = $$(cd $(TERRAFORM_DIR) && terraform output -raw ec2_vpn_id)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

ssm-vpn-instance: ## Connect to VPN instance via SSM Session Manager
	@INSTANCE_ID=$(INSTANCE_ID) && \
	echo "Connecting to $$INSTANCE_ID ..." && \
	aws ssm start-session --target $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION)

start-vpn-instance: ## Start VPN EC2 instance
	@INSTANCE_ID=$(INSTANCE_ID) && \
	STATE=$$(aws ec2 describe-instances --instance-ids $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION) --query 'Reservations[0].Instances[0].State.Name' --output text) && \
	if [ "$$STATE" = "running" ]; then \
		echo "Instance $$INSTANCE_ID is already running."; \
	else \
		echo "Starting $$INSTANCE_ID ..." && \
		aws ec2 start-instances --instance-ids $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION) > /dev/null && \
		echo "Waiting for instance to be running ..." && \
		aws ec2 wait instance-running --instance-ids $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION) && \
		echo "Instance $$INSTANCE_ID is now running."; \
	fi

stop-vpn-instance: ## Stop VPN EC2 instance
	@INSTANCE_ID=$(INSTANCE_ID) && \
	STATE=$$(aws ec2 describe-instances --instance-ids $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION) --query 'Reservations[0].Instances[0].State.Name' --output text) && \
	if [ "$$STATE" = "stopped" ]; then \
		echo "Instance $$INSTANCE_ID is already stopped."; \
	else \
		echo "Stopping $$INSTANCE_ID ..." && \
		aws ec2 stop-instances --instance-ids $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION) > /dev/null && \
		echo "Waiting for instance to stop ..." && \
		aws ec2 wait instance-stopped --instance-ids $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION) && \
		echo "Instance $$INSTANCE_ID is now stopped."; \
	fi

status-vpn-instance: ## Show VPN EC2 instance status
	@INSTANCE_ID=$(INSTANCE_ID) && \
	aws ec2 describe-instances --instance-ids $$INSTANCE_ID --profile $(AWS_PROFILE) --region $(AWS_REGION) \
		--query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,InstanceType:InstanceType}' \
		--output table

.PHONY: help ssm-vpn-instance start-vpn-instance stop-vpn-instance status-vpn-instance
