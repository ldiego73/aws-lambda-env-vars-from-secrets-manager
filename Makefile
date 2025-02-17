.PHONY: build_local build_x86 build_arm build_lambda_x86 build_lambda_arm deploy_cli_x86 deploy_cli_arm add_permissions_x86 add_permissions_arm remove_version dev clean

LAYER_NAME_X86 := env-vars-from-secrets-manager
LAYER_NAME_ARM := env-vars-from-secrets-manager-arm

build_local:
	@echo "Building from source..."
	@cargo build --release
	@echo "Build completed"

build_x86:
	@echo "Building for x86_64..."
	@cargo build --target x86_64-unknown-linux-gnu --release
	@echo "Build completed"

build_arm:
	@echo "Building for ARM64..."
	@cargo build --target aarch64-unknown-linux-gnu --release
	@echo "Build completed"

build_lambda_x86:
	@echo "Building Lambda layer for x86_64..."
	@cargo lambda build --extension --release --target x86_64-unknown-linux-gnu
	@rm -rf ./out
	@cp -R target/lambda/extensions ./out
	@cp ./scripts/retrieve-secrets ./out
	@chmod +x ./out/env-vars-from-secrets-manager
	@chmod +x ./out/retrieve-secrets
	@cd out && zip -r ../out-x86.zip *
	@echo "Build completed"

build_lambda_arm:
	@echo "Building Lambda layer for ARM64..."
	@cargo lambda build --extension --release --target aarch64-unknown-linux-gnu
	@rm -rf ./out
	@cp -R target/lambda/extensions ./out
	@cp ./scripts/retrieve-secrets ./out
	@chmod +x ./out/env-vars-from-secrets-manager
	@chmod +x ./out/retrieve-secrets
	@cd out && zip -r ../out-arm.zip *
	@echo "Build completed"

deploy_cli_x86:
	@echo "Deploying x86_64 layer..."
	@aws lambda publish-layer-version \
		--layer-name "$(LAYER_NAME_X86)" \
		--description "Layer for reading secrets manager and storing them in env variables (x86_64)" \
		--zip-file fileb://out-x86.zip \
		--compatible-architectures x86_64 \
		--compatible-runtimes provided.al2 provided.al2023 nodejs18.x nodejs20.x python3.10 python3.11 python3.12 \
		> response-x86.json
	@echo "Deploy completed"

deploy_cli_arm:
	@echo "Deploying ARM64 layer..."
	@aws lambda publish-layer-version \
		--layer-name "$(LAYER_NAME_ARM)" \
		--description "Layer for reading secrets manager and storing them in env variables (ARM64)" \
		--zip-file fileb://out-arm.zip \
		--compatible-architectures arm64 \
		--compatible-runtimes provided.al2 provided.al2023 nodejs18.x nodejs20.x python3.10 python3.11 python3.12 \
		> response-arm.json
	@echo "Deploy completed"

add_permissions_x86:
	@echo "Adding permissions for x86_64 layer..."
	$(eval EXTENSION_VERSION=$(shell jq -r '.Version' response-x86.json))
	@aws lambda add-layer-version-permission \
		--layer-name "$(LAYER_NAME_X86)" \
		--statement-id AWSLambdaExecute \
		--action lambda:GetLayerVersion \
		--principal "*" \
		--organization-id "$(ORG_ID)" \
		--version-number "$(EXTENSION_VERSION)"
	@echo "Permissions added"


add_permissions_by_account_x86:
	@echo "Adding permissions for x86_64 layer..."
	$(eval EXTENSION_VERSION=$(shell jq -r '.Version' response-x86.json))
	@aws lambda add-layer-version-permission \
		--layer-name "$(LAYER_NAME_X86)" \
		--statement-id AWSLambdaExecute \
		--action lambda:GetLayerVersion \
		--principal "$(ACCOUNT_ID)" \
		--version-number "$(EXTENSION_VERSION)"
	@echo "Permissions added"


add_permissions_by_account_arm:
	@echo "Adding permissions for ARM64 layer..."
	$(eval EXTENSION_VERSION=$(shell jq -r '.Version' response-arm.json))
	@aws lambda add-layer-version-permission \
		--layer-name "$(LAYER_NAME_ARM)" \
		--statement-id AWSLambdaExecute \
		--action lambda:GetLayerVersion \
		--principal "$(ACCOUNT_ID)" \
		--version-number "$(EXTENSION_VERSION)"
	@echo "Permissions added"

add_permissions_arm:
	@echo "Adding permissions for ARM64 layer..."
	$(eval EXTENSION_VERSION=$(shell jq -r '.Version' response-arm.json))
	@aws lambda add-layer-version-permission \
		--layer-name "$(LAYER_NAME_ARM)" \
		--statement-id AWSLambdaExecute \
		--action lambda:GetLayerVersion \
		--principal "*" \
		--organization-id "$(ORG_ID)" \
		--version-number "$(EXTENSION_VERSION)"
	@echo "Permissions added"

remove_x86_version:
	@echo "Removing version..."
	@aws lambda delete-layer-version \
		--layer-name "$(LAYER_NAME_X86)" \
		--version-number "$(VERSION)"
	@echo "Version removed"

remove_arm_version:
	@echo "Removing version..."
	@aws lambda delete-layer-version \
		--layer-name "$(LAYER_NAME_ARM)" \
		--version-number "$(VERSION)"
	@echo "Version removed"

dev:
	@echo "Starting your app using dev...."
	@cargo run -- --secrets $(SECRETS) --path $(PATH) --prefix secret

clean:
	@echo "Cleaning..."
	@cargo clean
	@echo "Clean completed"
