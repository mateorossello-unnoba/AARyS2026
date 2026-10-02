import boto3
import json
import os
from boto3.dynamodb.conditions import Key
from collections import defaultdict

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ['TABLE_NAME']
tabla = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    query_params = event.get('queryStringParameters') or {}
    juego_filtro = query_params.get('juego')

    if juego_filtro:
        respuesta = tabla.query(
            KeyConditionExpression=Key('juego').eq(juego_filtro)
        )
        items = respuesta.get('Items', [])
    else:
        respuesta = tabla.scan()
        items = respuesta.get('Items', [])

    diccionario_juegos = defaultdict(list)
    for item in items:
        diccionario_juegos[item['juego']].append({
            'jugador': item['jugador'],
            'puntaje': int(item['puntaje'])
        })

    resultado = {}
    for juego, scores in diccionario_juegos.items():
        scores_ordenados = sorted(scores, key=lambda x: x['puntaje'], reverse=True)[:10]
        resultado[juego] = scores_ordenados

    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(resultado)
    }
