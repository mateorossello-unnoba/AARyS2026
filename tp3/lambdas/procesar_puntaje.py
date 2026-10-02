import boto3
import json
import os

dynamodb = boto3.resource('dynamodb')
TABLE_NAME = os.environ['TABLE_NAME']
tabla = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    for record in event.get('Records', []):
        body = json.loads(record['body'])
        jugador = body['jugador']
        juego = body['juego']
        nuevo_puntaje = int(body['puntaje'])

        respuesta = tabla.get_item(Key={'juego': juego, 'jugador': jugador})
        item_actual = respuesta.get('Item')

        if not item_actual or nuevo_puntaje > int(item_actual.get('puntaje', 0)):
            tabla.put_item(
                Item={
                    'juego': juego,
                    'jugador': jugador,
                    'puntaje': nuevo_puntaje
                }
            )
            
            print(f"Éxito: Puntaje actualizado para {jugador} en {juego} ({nuevo_puntaje}).")
        else:
            print(f"Ignorado: {nuevo_puntaje} no supera el registro de {jugador} en {juego}.")
