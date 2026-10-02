# Trabajo Práctico AWS

**Esta es la guía paso a paso para reproducir la arquitectura solicitada en la práctica.**

Antes de comenzar, se debe poner en funcionamiento la imagen de MiniStack y configurar las credenciales ficticias, la región por defecto y el alias para interactuar correctamente:

```bash
docker run -d --name ministack -p 4566:4566 -v /var/run/docker.sock:/var/run/docker.sock ministackorg/ministack
```

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
alias awsl='aws --endpoint-url=http://localhost:4566'
```

### Frontend Estático y CloudFront

A partir del contenido en la carpeta `web`:

```bash
awsl s3 mb s3://gamecloud-web
```

```bash
awsl s3 website s3://gamecloud-web --index-document index.html
```

```bash
awsl s3 cp index.html s3://gamecloud-web
```

```bash
awsl cloudfront create-distribution --origin-domain-name gamecloud-web.s3.amazonaws.com
```

### Base de Datos en DynamoDB

```bash
aws dynamodb create-table \
  --table-name Puntajes \
  --attribute-definitions AttributeName=juego,AttributeType=S AttributeName=jugador AttributeType=S \
  --key-schema AttributeName=juego,KeyType=HASH AttributeName=jugador,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST
```

### Colas de Mensajes con SQS

```bash
awsl sqs create-queue --queue-name puntajes-dlq
```

```bash
awsl sqs create-queue --queue-name puntajes --attributes '{"VisibilityTimeout": "30","RedrivePolicy": "{\"deadLetterTargetArn\": \"arn:aws:sqs:us-east-1:000000000000:puntajes-dlq\", \"maxReceiveCount\": \"3\"}"}'
```

### Funciones Lambda e IAM

Tanto los comandos para crear el rol como los comandos para crear las funciones deben ejecutarse en sus debidas carpetas (`iam` y `lambdas`):

```bash
awsl iam create-role --role-name gamecloud-lambda-role --assume-role-policy-document file://trust-lambda.json
```

```bash
awsl iam put-role policy \
  --role-name gamecloud-lambda-role \
  --policy-name permisos-estrictos \
  --policy-document file://politicas-lambdas.json
```

**ranking.py:**

```bash
zip ranking.zip ranking.py

awsl lambda create-function \
  --function-name ranking \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler ranking.lambda_handler \
  --zip-file fileb://ranking.zip \
  --environment "Variables={TABLE_NAME=Puntajes}"
```

**recibir_puntaje.py:**

```bash
zip recibir_puntaje.zip recibir_puntaje.py

awsl lambda create-function \
  --function-name recibir_puntaje \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler recibir_puntaje.lambda_handler \
  --zip-file fileb://recibir_puntaje.zip \
  --environment Variables="{QUEUE_URL=http://localhost:4566/000000000000/puntajes}"
```

**procesar_puntaje.py:**

```bash
zip procesar_puntaje.zip procesar_puntaje.py

awsl lambda create-function \
  --function-name procesar_puntaje \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler procesar_puntaje.lambda_handler \
  --zip-file fileb://procesar_puntaje.zip \
  --environment "Variables={TABLE_NAME=Puntajes}"
```

Se conecta procesar_puntaje con la cola puntajes mediante un Event Source Mapping.

```bash
awsl lambda create-event-source-mapping \
  --function-name procesar_puntaje \
  --event-source-arn arn:aws:sqs:us-east-1:000000000000:puntajes
```

### API Gateway

```bash
awsl apigatewayv2 create-api \
  --name gamecloud-api \
  --protocol-type HTTP \
  --cors-configuration AllowMethods="GET,POST,OPTIONS",AllowOrigins="*",AllowHeaders="Content-Type"
```

_(Se debe recordar el `ApiId` que devuelve este comando para configuraciones posteriores)._

Configurar integraciones:

```bash
awsl apigatewayv2 create-integration \
  --api-id ApiId \
  --integration-type AWS_PROXY \
  --integration-uri arn:aws:lambda:us-east-1:000000000000:function:ranking \
  --payload-format-version 2.0
```

_(Reemplazar por el `ApiId` correspondiente y recordar el `IntegrationId` que devuelve este comando para configuraciones posteriores)._

```bash
awsl apigatewayv2 create-integration \
  --api-id ApiId \
  --integration-type AWS_PROXY \
  --integration-uri arn:aws:lambda:us-east-1:000000000000:function:recibir_puntaje \
  --payload-format-version 2.0
```

_(Reemplazar por el `ApiId` correspondiente y recordar el `IntegrationId` que devuelve este comando para configuraciones posteriores)._

Configurar rutas:

```bash
awsl apigatewayv2 create-route \
  --api-id ApiId \
  --route-key "GET /ranking" \
  --target "integrations/IntegrationId"
```

_(Reemplazar por el `ApiId` e `IntegrationId` correspondiente)._

```bash
awsl apigatewayv2 create-route \
  --api-id ApiId \
  --route-key "POST /scores" \
  --target "integrations/IntegrationId"
```

_(Reemplazar por el `ApiId` e `IntegrationId` correspondiente)._

Otorgar permisos de invocación:

```bash
awsl lambda add-permission \
  --function-name ranking \
  --statement-id api-ranking \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com
```

```bash
awsl lambda add-permission \
  --function-name recibir_puntaje \
  --statement-id api-recibir-puntaje \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com
```

Configurar el API Gateway:

```bash
awsl apigatewayv2 create-stage \
  --api-id ApiId \
  --stage-name \$default \
  --auto-deploy \
  --default-route-settings ThrottlingBurstLimit=200,ThrottlingRateLimit=100
```

_(Reemplazar por el `ApiId` correspondiente)._

Por último, se debe reemplazar en el archivo `config.js` (ubicado en la carpeta `web`) la sección `<API_ID>` por el valor del ApiId generado previamente. Luego, el archivo debe ser copiado a S3:

```javascript
window.GAMECLOUD_API = "http://<API_ID>.execute-api.localhost:4566";
```

```bash
awsl s3 cp config.js s3://gamecloud-web/
```

Para probar el despliegue: `http://gamecloud-web.s3.localhost:4566/index.html`

### Pruebas

Envío de un puntaje válido.

```bash
curl -i -X POST http://ApiId.execute-api.localhost:4566/scores \
  -H 'Content-Type: application/json' \
  -d '{"jugador":"Nombre","juego":"Juego","puntaje":Puntaje}'
```

_(Reemplazar por el `ApiId` y valores de envío correspondientes)._

Envío de un puntaje inválido por juego inexistente.

```bash
curl -i -X POST http://ApiId.execute-api.localhost:4566/scores \
  -H 'Content-Type: application/json' \
  -d '{"jugador":"Nombre","puntaje":Puntaje}'
```

_(Reemplazar por el `ApiId` y valores de envío correspondientes)._

Para corroborar el envío de un puntaje menor al mejor puntaje de un jugador, se debe enviar un puntaje válido para dicho jugador y luego otro con una puntuación menor.

Consulta de GET /ranking sin parámetro y con parámetro.

```bash
curl "http://ApiId.execute-api.localhost:4566/ranking"
```

```bash
curl "http://ApiId.execute-api.localhost:4566/ranking?juego=Juego"
```

_(Reemplazar por el `ApiId` y valores de envío correspondientes)._

Para simular el pico de solicitudes de un torneo enviando 50 puntajes en paralelo.

```bash
( for i in {1..50}; do curl -s -X POST http://ApiId.execute-api.localhost:4566/scores -H 'Content-Type: application/json' -d "{\"jugador\":\"bot$i\",\"juego\":\"Juego\",\"puntaje\":$i}" > /dev/null & done ) &> /dev/null
```

_(Reemplazar por el `ApiId` y valores de envío correspondientes)._

Para enviar directamente a la cola de mensajes un mensaje con contenido inválido (que no es JSON) y verificar que termine en la DLQ.

```bash
awsl sqs send-message \
  --queue-url http://localhost:4566/000000000000/puntajes \
  --message-body "esto no es un JSON" \
  --query 'MessageId'
```

```bash
awsl sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/puntajes-dlq \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes'
```

Para revisar el registro de procesar_puntaje en CloudWatch Logs.

```bash
awsl logs filter-log-events \
  --log-group-name /aws/lambda/procesar_puntaje \
  --query 'events[*].message' \
  --output text | grep -oE '(Éxito|Ignorado)[^.]+\.' | tail -n 1000
```
