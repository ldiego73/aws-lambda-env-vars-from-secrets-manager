.PHONY: build_local build_release build_lambda_release deploy_cli add_permissions remove_version remove_version dev clean

build_local:
	@echo "Building from source..."
	@cargo build --release
	@echo "Build completed"

build_release:
	@echo "Building from source..."
	@cargo build --target x86_64-unknown-linux-gnu --release
	@echo "Build completed"

build_lambda_release:
	@echo "Building from source..."
	@cargo lambda build --extension --release
	@rm -rf ./out
	@cp -R target/lambda/extensions ./out
	@cp ./scripts/retrieve-secrets ./out
	@chmod +x ./out/env-vars-from-secrets-manager
	@chmod +x ./out/retrieve-secrets
	@cd out && zip -r ../out.zip *
	@echo "Build completed"

deploy_cli:
	@echo "Deploying..."
	@aws lambda publish-layer-version \
		--layer-name env-vars-from-secrets-manager \
		--description "Layer for read secrets manager and store them in env variables" \
		--zip-file fileb://out.zip \
		--compatible-architectures x86_64 \
		--compatible-runtimes provided.al2 provided.al2023 nodejs18.x nodejs20.x python3.10 python3.11 python3.12 \
		> response.json
	@echo "Deploy completed"

add_permissions:
	@echo "Adding permissions..."
	$(eval EXTENSION_VERSION=$(shell jq -r '.Version' response.json))
	@aws lambda add-layer-version-permission \
		--layer-name env-vars-from-secrets-manager \
		--statement-id AWSLambdaExecute \
		--action lambda:GetLayerVersion \
		--principal "*" \
		--organization-id "$(ORG_ID)"  \
		--version-number "$(EXTENSION_VERSION)"
	@echo "Permissions added"

remove_version:
	@echo "Removing version..."
	@aws lambda delete-layer-version \
		--layer-name env-vars-from-secrets-manager \
		--version-number "$(VERSION)"
	@echo "Version removed"

dev:
	@echo "Starting your app using dev...."
	@cargo run -- --secrets $(SECRETS) --path $(PATH) --prefix secret

clean:
	@echo "Cleaning..."
	@cargo clean
	@echo "Clean completed"