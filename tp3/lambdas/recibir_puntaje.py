import boto3
import json
import os

sqs = boto3.client('sqs')
QUEUE_URL = os.environ['QUEUE_URL']

def lambda_handler(event, context):    
    try:
        body_str = event.get('body', '{}')
        if not body_str:
            body_str = '{}'
        
        datos = json.loads(body_str)
        jugador = datos.get('jugador')
        juego = datos.get('juego')
        puntaje = datos.get('puntaje')

        if not jugador or not juego or not isinstance(puntaje, int):
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Datos inválidos'})
            }

        sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps({'jugador': jugador, 'juego': juego, 'puntaje': puntaje})
        )
        
        return {
            'statusCode': 202,
            'body': json.dumps({'mensaje': 'Accepted'})
        }
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Formato JSON inválido'})
        }
