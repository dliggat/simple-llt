STAGING_DIR   := package
BUILDS_DIR    := builds
PARAMS_FILE   := cloudformation/parameters.json
EXCLUDE_DIRS  := .git|tests|cloudformation|requirements|$(STAGING_DIR)|$(BUILDS_DIR)
PIP_COMMAND   := pip install -r
AWS_COMMAND   := aws # --ca-bundle /etc/pki/ca-trust/source/anchors/MDA-SWG.pem

.PHONY: init create-stack update-stack delete-stack describe-stack invoke test clean build update _check_config _check_stack_exists _is_user_authenticated

# Read the cloudformation/parameters.json file for the ProjectName and EnvionmentName.
# Use these to name the CloudFormation stack.
PROJECT_NAME = $(shell cat $(PARAMS_FILE) | python -c 'import sys, json; j = [i for i in json.load(sys.stdin) if i["ParameterKey"]=="ProjectName"][0]["ParameterValue"]; print(j)')
ENVIRONMENT_NAME = $(shell cat $(PARAMS_FILE) | python -c 'import sys, json; j = [i for i in json.load(sys.stdin) if i["ParameterKey"]=="EnvironmentName"][0]["ParameterValue"]; print(j)')
S3_KEY_NAME = $(shell cat $(PARAMS_FILE) | python -c 'import sys, json; j = [i for i in json.load(sys.stdin) if i["ParameterKey"]=="S3DeploymentFileKey"][0]["ParameterValue"]; print(j)')
S3_BUCKET_NAME = $(shell cat $(PARAMS_FILE) | python -c 'import sys, json; j = [i for i in json.load(sys.stdin) if i["ParameterKey"]=="S3DeploymentBucketName"][0]["ParameterValue"]; print(j)')
STACK_NAME := $(PROJECT_NAME)-$(ENVIRONMENT_NAME)

_is_user_authenticated:
	$(AWS_COMMAND) sts get-caller-identity > /dev/null

_check_stack_exists:
	$(AWS_COMMAND) cloudformation describe-stacks --stack-name $(STACK_NAME) > /dev/null

_check_config:
ifeq ($(S3_BUCKET_NAME),)
	$(error Please set your S3 bucket name in "cloudformation/parameters.json" and re-run.)
endif

init:
	$(PIP_COMMAND) requirements/dev.txt
	PYTHONPATH=./awslambda/utils/ python -m configure

create-stack: _check_config _is_user_authenticated build
	$(eval $@FILE := $(shell ls -t $(BUILDS_DIR) | head -n1 ))
	$(AWS_COMMAND) s3 cp "$(BUILDS_DIR)/$($@FILE)" "s3://$(S3_BUCKET_NAME)/$(S3_KEY_NAME)"
	$(AWS_COMMAND) cloudformation create-stack \
	--stack-name $(STACK_NAME) \
	--template-body file://cloudformation/template.yaml \
	--parameters file://cloudformation/parameters.json \
	--capabilities CAPABILITY_IAM

update-stack: _is_user_authenticated
	$(AWS_COMMAND) cloudformation update-stack \
	--stack-name $(STACK_NAME) \
	--template-body file://cloudformation/template.yaml \
	--parameters file://cloudformation/parameters.json \
	--capabilities CAPABILITY_IAM

delete-stack: _is_user_authenticated
	$(AWS_COMMAND) cloudformation delete-stack \
	--stack-name $(STACK_NAME)

describe-stack: _is_user_authenticated
	$(AWS_COMMAND) cloudformation describe-stacks \
	--stack-name $(STACK_NAME)

invoke:
	PYTHONPATH=./ IS_LOCAL=true ProjectName=$(PROJECT_NAME) EnvironmentName=$(ENVIRONMENT_NAME) python awslambda/index.py

test:
	py.test -rsxX -q -s tests

clean:
	rm -rf $(STAGING_DIR)
	rm -rf $(BUILDS_DIR)

build: test
	mkdir -p $(STAGING_DIR)
	mkdir -p $(BUILDS_DIR)
	$(PIP_COMMAND) requirements/lambda.txt -t $(STAGING_DIR)
	cp awslambda/*.py $(STAGING_DIR)
	cp awslambda/*.yaml $(STAGING_DIR)
	# Copy all other directories, excluding the blacklist.
	$(eval $@DEPLOY_DIRS := $(shell find . -type d -maxdepth 1 -mindepth 1 | grep -v  -E '$(EXCLUDE_DIRS)'))
	cp -R $($@DEPLOY_DIRS) $(STAGING_DIR)
	find $(STAGING_DIR) -type f -ipath '*.pyc' -delete  # Get rid of unnecessary .pyc files.
	find $(STAGING_DIR) -type f | xargs chmod a+rx
	find $(STAGING_DIR) -type d | xargs chmod a+rx
	$(eval $@FILE := deploy-$(shell date +%Y-%m-%d_%H-%M).zip)
	cd $(STAGING_DIR); zip -r $($@FILE) ./*; mv *.zip ../$(BUILDS_DIR)
	@echo "Built $(BUILDS_DIR)/$($@FILE)"
	rm -rf $(STAGING_DIR)

update: _is_user_authenticated _check_stack_exists build
	$(eval $@FILE := $(shell ls -t $(BUILDS_DIR) | head -n1 ))
	$(eval $@ARN := $(shell $(AWS_COMMAND) cloudformation describe-stacks --stack-name $(STACK_NAME) --query 'Stacks[].Outputs[?OutputKey==`LambdaFunctionARN`].OutputValue | [0] | [0]' --output text))
	$(AWS_COMMAND) s3 cp "$(BUILDS_DIR)/$($@FILE)" "s3://$(S3_BUCKET_NAME)/$(S3_KEY_NAME)"
	$(AWS_COMMAND) lambda update-function-code --function-name "$($@ARN)" --s3-bucket "$(S3_BUCKET_NAME)" --s3-key "$(S3_KEY_NAME)"
	@echo "Lambda source code updated successfully."
