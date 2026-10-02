#!/bin/bash

printf '%s' "Desplegando en MiniStack"
printf '\n'

# Variables de entorno requeridas
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

awsl() {
    aws --endpoint-url=http://localhost:4566 "$@"
}

printf '\n'
printf '%s' "--- S3 y CloudFront ---"
printf '\n'
printf '\n'
awsl s3 mb s3://gamecloud-web
awsl s3 website s3://gamecloud-web --index-document index.html
awsl s3 cp web/index.html s3://gamecloud-web/
printf '\n'
awsl cloudfront create-distribution --origin-domain-name gamecloud-web.s3.amazonaws.com

printf '\n'
printf '%s' "--- Base de datos en DynamoDB ---"
printf '\n'
printf '\n'
awsl dynamodb create-table \
  --table-name Puntajes \
  --attribute-definitions AttributeName=juego,AttributeType=S AttributeName=jugador,AttributeType=S \
  --key-schema AttributeName=juego,KeyType=HASH AttributeName=jugador,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

printf '\n'
printf '%s' "--- Colas de Mensajes con SQS ---"
printf '\n'
printf '\n'
awsl sqs create-queue --queue-name puntajes-dlq
awsl sqs create-queue --queue-name puntajes --attributes '{"VisibilityTimeout": "30", "RedrivePolicy": "{\"deadLetterTargetArn\": \"arn:aws:sqs:us-east-1:000000000000:puntajes-dlq\", \"maxReceiveCount\": \"3\"}"}'

printf '\n'
printf '%s' "--- IAM ---"
printf '\n'
printf '\n'
awsl iam create-role --role-name gamecloud-lambda-role --assume-role-policy-document file://iam/trust-lambda.json
awsl iam put-role-policy \
  --role-name gamecloud-lambda-role \
  --policy-name permisos-estrictos \
  --policy-document file://iam/politica-lambdas.json

printf '\n'
printf '%s' "--- Lambda ---"
printf '\n'
printf '\n'
cd lambdas

zip ranking.zip ranking.py
awsl lambda create-function \
  --function-name ranking \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler ranking.lambda_handler \
  --zip-file fileb://ranking.zip \
  --environment "Variables={TABLE_NAME=Puntajes}"
rm ranking.zip

printf '\n'

zip recibir_puntaje.zip recibir_puntaje.py
awsl lambda create-function \
  --function-name recibir_puntaje \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler recibir_puntaje.lambda_handler \
  --zip-file fileb://recibir_puntaje.zip \
  --environment 'Variables={QUEUE_URL="http://localhost:4566/000000000000/puntajes"}'
rm recibir_puntaje.zip

printf '\n'

zip procesar_puntaje.zip procesar_puntaje.py
awsl lambda create-function \
  --function-name procesar_puntaje \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler procesar_puntaje.lambda_handler \
  --zip-file fileb://procesar_puntaje.zip \
  --environment "Variables={TABLE_NAME=Puntajes}"
rm procesar_puntaje.zip

cd ..

printf '\n'
printf '%s' "--- Event Source Mapping de SQS y procesar_puntaje ---"
printf '\n'
printf '\n'
awsl lambda create-event-source-mapping \
  --function-name procesar_puntaje \
  --event-source-arn arn:aws:sqs:us-east-1:000000000000:puntajes

printf '\n'
printf '%s' "--- API Gateway ---"
API_ID=$(awsl apigatewayv2 create-api \
  --name gamecloud-api \
  --protocol-type HTTP \
  --cors-configuration AllowMethods="GET,POST,OPTIONS",AllowOrigins="*",AllowHeaders="Content-Type" \
  --query 'ApiId' \
  --output text
)
printf '\n'
printf '\n'
printf '%s' "API Gateway con ID $API_ID creado exitosamente."
printf '\n'

INT_RANKING=$(awsl apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type AWS_PROXY \
  --integration-uri arn:aws:lambda:us-east-1:000000000000:function:ranking \
  --payload-format-version 2.0 \
  --query 'IntegrationId' --output text
)

INT_RECIBIR_PUNTAJE=$(awsl apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type AWS_PROXY \
  --integration-uri arn:aws:lambda:us-east-1:000000000000:function:recibir_puntaje \
  --payload-format-version 2.0 \
  --query 'IntegrationId' --output text
)

printf '\n'

awsl apigatewayv2 create-route --api-id $API_ID --route-key "GET /ranking" --target "integrations/$INT_RANKING"
awsl apigatewayv2 create-route --api-id $API_ID --route-key "POST /scores" --target "integrations/$INT_RECIBIR_PUNTAJE"

printf '\n'

awsl lambda add-permission --function-name ranking --statement-id api-ranking --action lambda:InvokeFunction --principal apigateway.amazonaws.com
awsl lambda add-permission --function-name recibir_puntaje --statement-id api-recibir-puntaje --action lambda:InvokeFunction --principal apigateway.amazonaws.com

printf '\n'

awsl apigatewayv2 create-stage --api-id $API_ID --stage-name \$default --auto-deploy --default-route-settings ThrottlingBurstLimit=200,ThrottlingRateLimit=100

printf '\n'
printf '%s' "--- Actualizar config.js y subir a S3 ---"
printf '\n'
printf '\n'
printf 'window.GAMECLOUD_API = "http://'$API_ID'.execute-api.localhost:4566";' > web/config.js
awsl s3 cp web/config.js s3://gamecloud-web/

printf '\n'
printf '%s' "--- Despliegue en MiniStack finalizado ---"
printf '\n'
printf '%s' "Frontend - http://gamecloud-web.s3.localhost:4566/index.html"
printf '\n'
printf '%s' "API URL - http://$API_ID.execute-api.localhost:4566"
printf '\n'
