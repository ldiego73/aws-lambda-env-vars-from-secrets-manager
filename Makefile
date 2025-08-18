.PHONY: build_local build_x86 build_arm build_lambda_x86 build_lambda_arm deploy_cli_x86 deploy_cli_arm add_permissions_x86 add_permissions_arm add_permissions_by_account_x86 add_permissions_by_account_arm remove_x86_version remove_arm_version clean

# Variables
LAYER_NAME_X86 := env-vars-from-secrets-manager
LAYER_NAME_ARM := env-vars-from-secrets-manager-arm
TARGET_X86 := x86_64-unknown-linux-gnu
TARGET_ARM := aarch64-unknown-linux-gnu
COMPATIBLE_RUNTIMES := provided.al2 provided.al2023

build_local:
	@echo "Building from source..."
	@cargo build --release
	@echo "Build completed"

define package_template
	@echo "Building Lambda layer for $(2)..."
	@cargo lambda build --extension --release --target $(1)
	@rm -rf ./out
	@cp -R target/lambda/extensions ./out
	@chmod +x ./out/aws-lambda-logs-http-destination
	@cd out && zip -r ../$(3) *
	@echo "Build completed"
endef

package_x86:
	$(call package_template,$(TARGET_X86),x86_64,out-x86.zip)

package_arm:
	$(call package_template,$(TARGET_ARM),ARM64,out-arm.zip)

define deploy_template
	@echo "Deploying $(3) layer..."
	@aws lambda publish-layer-version \
		--layer-name "$(1)" \
		--description "Layer for AWS Lambda Logs HTTP Destination Extension ($(3))" \
		--zip-file fileb://$(2) \
		--compatible-architectures $(4) \
		--compatible-runtimes $(COMPATIBLE_RUNTIMES) \
		--region "$(REGION)" \
		> $(5)
	@echo "Deploy completed"
endef

deploy_x86:
	$(call deploy_template,$(LAYER_NAME_X86),out-x86.zip,x86_64,x86_64,response-x86.json)

deploy_arm:
	$(call deploy_template,$(LAYER_NAME_ARM),out-arm.zip,ARM64,arm64,response-arm.json)

define add_permissions_template
	@echo "Adding permissions for $(3) layer..."
	$(eval EXTENSION_VERSION=$(shell jq -r '.Version' $(2)))
	@aws lambda add-layer-version-permission \
		--layer-name "$(1)" \
		--statement-id AWSLambdaExecute \
		--action lambda:GetLayerVersion \
		--principal "*" \
		--organization-id "$(ORG_ID)" \
		--region "$(REGION)" \
		--version-number "$(EXTENSION_VERSION)"
	@echo "Permissions added"
endef

add_permissions_x86:
	$(call add_permissions_template,$(LAYER_NAME_X86),response-x86.json,x86_64)

add_permissions_arm:
	$(call add_permissions_template,$(LAYER_NAME_ARM),response-arm.json,ARM64)

define add_permissions_by_account_template
	@echo "Adding permissions for $(3) layer..."
	$(eval EXTENSION_VERSION=$(shell jq -r '.Version' $(2)))
	@aws lambda add-layer-version-permission \
		--layer-name "$(1)" \
		--statement-id AWSLambdaExecute \
		--action lambda:GetLayerVersion \
		--principal "$(ACCOUNT_ID)" \
		--region "$(REGION)" \
		--version-number "$(EXTENSION_VERSION)"
	@echo "Permissions added"
endef

add_permissions_by_account_x86:
	$(call add_permissions_by_account_template,$(LAYER_NAME_X86),response-x86.json,x86_64)

add_permissions_by_account_arm:
	$(call add_permissions_by_account_template,$(LAYER_NAME_ARM),response-arm.json,ARM64)

define remove_version_template
	@echo "Removing version..."
	@aws lambda delete-layer-version \
		--layer-name "$(1)" \
		--region "$(REGION)" \
		--version-number "$(VERSION)"
	@echo "Version removed"
endef

remove_x86_version:
	$(call remove_version_template,$(LAYER_NAME_X86))

remove_arm_version:
	$(call remove_version_template,$(LAYER_NAME_ARM))

clean:
	@echo "Cleaning..."
	@cargo clean
	@echo "Clean completed"
