#!/bin/bash

printf '%s' "Limpiando MiniStack"
printf '\n'

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

awsl() {
    aws --endpoint-url=http://localhost:4566 "$@"
}

printf '\n'
printf '%s' "--- API Gateway ---"
printf '\n'
printf '\n'

API_ID=$(awsl apigatewayv2 get-apis --query 'Items[0].ApiId' --output text 2>/dev/null)
if [ "$API_ID" != "None" ] && [ -n "$API_ID" ]; then
    awsl apigatewayv2 delete-api --api-id $API_ID
    printf '%s' "API Gateway ($API_ID) eliminado exitosamente."
    printf '\n'
else
    printf '%s' "No se encontró API Gateway para eliminar."
    printf '\n'
fi

printf '\n'
printf '%s' "--- Event Source Mapping ---"
printf '\n'
printf '\n'

MAPPING_UUID=$(awsl lambda list-event-source-mappings --function-name procesar_puntaje --query 'EventSourceMappings[0].UUID' --output text 2>/dev/null)
if [ "$MAPPING_UUID" != "None" ] && [ -n "$MAPPING_UUID" ]; then
    awsl lambda delete-event-source-mapping --uuid $MAPPING_UUID
    printf '\n'
    printf '%s' "Event Source Mapping ($MAPPING_UUID) eliminado."
    printf '\n'
else
    printf '%s' "No se encontró Event Source Mapping."
    printf '\n'
fi

printf '\n'
printf '%s' "--- Lambda ---"
printf '\n'
printf '\n'

awsl lambda delete-function --function-name ranking 2>/dev/null
awsl lambda delete-function --function-name recibir_puntaje 2>/dev/null
awsl lambda delete-function --function-name procesar_puntaje 2>/dev/null
printf '\n'
printf '%s' "Funciones eliminadas."
printf '\n'

printf '\n'
printf '%s' "--- IAM ---"
printf '\n'
printf '\n'

awsl iam delete-role-policy --role-name gamecloud-lambda-role --policy-name permisos-estrictos 2>/dev/null
awsl iam delete-role --role-name gamecloud-lambda-role 2>/dev/null
printf '%s' "Rol y políticas de IAM desvinculados y eliminados."
printf '\n'

printf '\n'
printf '%s' "--- Colas de Mensajes con SQS ---"
printf '\n'
printf '\n'

awsl sqs delete-queue --queue-url http://localhost:4566/000000000000/puntajes 2>/dev/null
awsl sqs delete-queue --queue-url http://localhost:4566/000000000000/puntajes-dlq 2>/dev/null
printf '%s' "Colas SQS (principal y DLQ) eliminadas."
printf '\n'

printf '\n'
printf '%s' "--- Base de datos en DynamoDB ---"
printf '\n'
printf '\n'

awsl dynamodb delete-table --table-name Puntajes 2>/dev/null
printf '\n'
printf '%s' "Tabla Puntajes eliminada."
printf '\n'

printf '\n'
printf '%s' "--- CloudFront ---"
printf '\n'
printf '\n'

CF_ID=$(awsl cloudfront list-distributions --query 'DistributionList.Items[0].Id' --output text 2>/dev/null)
if [ "$CF_ID" != "None" ] && [ -n "$CF_ID" ]; then
    ETAG=$(awsl cloudfront get-distribution --id $CF_ID --query 'ETag' --output text 2>/dev/null)
    awsl cloudfront delete-distribution --id $CF_ID --if-match $ETAG 2>/dev/null
    printf '%s' "Distribución de CloudFront ($CF_ID) eliminada."
    printf '\n'
else
    printf '%s' "No se encontró distribución de CloudFront para eliminar."
    printf '\n'
fi

printf '\n'
printf '%s' "--- S3 ---"
printf '\n'
printf '\n'

awsl s3 rm s3://gamecloud-web --recursive 2>/dev/null
awsl s3 rb s3://gamecloud-web 2>/dev/null
printf '\n'
printf '%s' "Bucket gamecloud-web vaciado y destruido."
printf '\n'

printf '\n'
printf '%s' "--- Limpieza de MiniStack finalizada ---"
printf '\n'
printf '%s' "Infraestructura eliminada correctamente."
printf '\n'
