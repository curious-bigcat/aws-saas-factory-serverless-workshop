#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

if ! [ -x "$(command -v jq)" ]; then
	echo "Installing jq"
    sudo yum install -y jq
fi

echo "Setting environment variables"
MY_AWS_REGION=$(aws configure list | grep region | awk '{print $2}')
echo "AWS Region = $MY_AWS_REGION"

STACK_OUTPUTS=$(aws cloudformation describe-stacks | jq -r '.Stacks[] | select(.Outputs != null) | .Outputs[]')

API_GATEWAY_URL=$(echo $STACK_OUTPUTS | jq -r 'select(.OutputKey == "ApiGatewayEndpointLab3") | .OutputValue')
echo "API Gateway Invoke URL = $API_GATEWAY_URL"

S3_WEBSITE_BUCKET=$(echo $STACK_OUTPUTS | jq -r 'select(.OutputKey == "WebsiteS3Bucket") | .OutputValue')
echo "S3 website bucket = $S3_WEBSITE_BUCKET"

CLOUDFRONT_DISTRIBUTION=$(echo $STACK_OUTPUTS | jq -r 'select(.OutputKey == "CloudFrontDistributionDNS") | .OutputValue')
echo "CloudFront distribution URL = $CLOUDFRONT_DISTRIBUTION"
echo

if [ -z "$API_GATEWAY_URL" ] || [ -z "$S3_WEBSITE_BUCKET" ] || [ -z "$CLOUDFRONT_DISTRIBUTION" ]; then
	echo "Missing required environment variables. Please make sure the lab3 CloudFormation stack has completed successfully."
	exit 1
fi

# Edit src/shared/config.js in the ReactJS codebase
# set base_url to the REST API stage v1 invoke URL
echo "Configuring React to talk to API Gateway"
cd /home/ec2-user/environment/saas-factory-serverless-workshop/lab2/client
sed -i -r -e 's|(^\s+)(base_url: )("https://.+\.execute-api\..+\.amazonaws\.com/v1")|//LAB 2\1\2\3\n\1\2"'"${API_GATEWAY_URL}"'"|g' src/shared/config.js

echo
echo "Installing NodeJS dependencies"
rm -f package-lock.json
npm install npm-force-resolutions
npm install

echo
echo "Building React app"
npm run build

# Setting the cache control metadata so that we don't have to invalidate
# (and wait for) the CloudFront distribution. You wouldn't do this in real life.
echo
echo "Uploading React app to S3 website bucket"
cd build
aws s3 sync --delete --cache-control no-store . s3://$S3_WEBSITE_BUCKET

# Order Service lambdas are cold. Warm them up to improve the workshop experience.
curl -s -H "Accept: application/json" -H "Content-Type: application/json" "$API_GATEWAY_URL/orders" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" "$API_GATEWAY_URL/orders/00000000-0000-0000-0000-000000000000?source=warmup" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" -X POST -d '{"source":"warmup"}' "$API_GATEWAY_URL/orders" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" -X PUT -d '{"source":"warmup"}' "$API_GATEWAY_URL/orders/00000000-0000-0000-0000-000000000000" > /dev/null
#curl -s -H "Accept: application/json" -H "Content-Type: application/json" -X DELETE -d '{"source":"warmup"}' "$API_GATEWAY_URL/orders/00000000-0000-0000-0000-000000000000" > /dev/null

echo
echo "Access your website at..."
echo $CLOUDFRONT_DISTRIBUTION
echo

