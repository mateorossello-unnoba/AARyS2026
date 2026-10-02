#!/bin/bash

printf '%s' "Probando MiniStack"
printf '\n'

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

awsl() {
    aws --endpoint-url=http://localhost:4566 "$@"
}

API_ID=$(awsl apigatewayv2 get-apis --query 'Items[0].ApiId' --output text)
API_URL="http://${API_ID}.execute-api.localhost:4566"
MAPPING_UUID=$(awsl lambda list-event-source-mappings --function-name procesar_puntaje --query 'EventSourceMappings[0].UUID' --output text)

printf '\n'
printf '%s' "--- Pruebas de API y procesamiento ---"
printf '\n'
printf '\n'

printf '%s' "Envío de un puntaje válido (Esperando HTTP 202)"
printf '\n'
printf '\n'
curl -i -X POST $API_URL/scores \
  -H 'Content-Type: application/json' \
  -d '{"jugador":"ana","juego":"doom","puntaje":9800}'

printf '\n'
printf '\n'
printf '%s' "Envío de un puntaje inválido (Falta el juego - Esperando HTTP 400)"
printf '\n'
printf '\n'
curl -i -X POST $API_URL/scores \
  -H 'Content-Type: application/json' \
  -d '{"jugador":"mateo","puntaje":5000}'

printf '\n'
printf '\n'
printf '%s' "Envío de puntaje menor al existente (Silencioso y no se procesa)"
curl -s -X POST $API_URL/scores \
  -H 'Content-Type: application/json' \
  -d '{"jugador":"ana","juego":"doom","puntaje":100}' > /dev/null

sleep 6

printf '\n'
printf '\n'
printf '%s' "Consulta de GET /ranking general"
printf '\n'
curl -s $API_URL/ranking

printf '\n'
printf '\n'
printf '%s' "Consulta de GET /ranking filtrado por juego (juego=doom)"
printf '\n'
curl -s "$API_URL/ranking?juego=doom"

printf '\n'
printf '\n'
printf '%s' "Simulando pico de 50 solicitudes en paralelo"

awsl lambda update-event-source-mapping --uuid $MAPPING_UUID --no-enabled > /dev/null
sleep 2

printf '\n'
( for i in {1..50}; do curl -s -X POST $API_URL/scores -H 'Content-Type: application/json' -d "{\"jugador\":\"bot$i\",\"juego\":\"pacman\",\"puntaje\":$i}" > /dev/null & done ) &> /dev/null
sleep 6

printf '\n'
awsl sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/puntajes --attribute-names ApproximateNumberOfMessages --query 'Attributes'

printf '\n'
awsl lambda update-event-source-mapping --uuid $MAPPING_UUID --enabled > /dev/null

printf '\n'
sleep 6
awsl sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/puntajes --attribute-names ApproximateNumberOfMessages --query 'Attributes'

printf '\n'
printf '%s' "Dead-Letter Queue (Mensaje inválido directo a SQS)"
printf '\n'
printf '\n'
awsl sqs send-message --queue-url http://localhost:4566/000000000000/puntajes --message-body "esto no es un JSON" > /dev/null

sleep 120
awsl sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/puntajes-dlq --attribute-names ApproximateNumberOfMessages --query 'Attributes'

printf '\n'
printf '%s' "Extracción de registros en CloudWatch"
printf '\n'
printf '\n'
awsl logs filter-log-events \
  --log-group-name /aws/lambda/procesar_puntaje \
  --query 'events[*].message' \
  --output text | grep -oE '(Éxito|Ignorado)[^.]+\.' | tail -n 10

printf '\n'
printf '%s' "--- Pruebas en MiniStack finalizadas ---"
printf '\n'
printf '%s' "Todas las operaciones de prueba fueron ejecutadas."
printf '\n'
