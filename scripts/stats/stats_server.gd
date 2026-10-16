class_name StatsServer
extends RefCounted
## Dirección del servidor local de estadísticas (carpeta server/ del
## repositorio). El juego nunca habla con la base de datos: solo envía JSON por
## HTTP a este servidor, que corre en la misma máquina.

const BASE_URL := "http://127.0.0.1:8765"
## Segundos máximos de espera por respuesta. Con el servidor apagado la
## conexión falla de inmediato; esto cubre un servidor colgado.
const REQUEST_TIMEOUT := 3.0
const JSON_HEADERS := ["Content-Type: application/json", "Accept: application/json"]
