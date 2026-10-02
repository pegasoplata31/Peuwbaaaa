# Guante-De-Voz — App Android BLE

Aplicación Flutter para el proyecto **Beyond Word / Guante-De-Voz**.

## Qué hace

- Se conecta por **Bluetooth Low Energy (BLE)** a:
  - `SmartGlove_Left`
  - `SmartGlove_Right`
- Usa:
  - Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
  - Characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`
- Puede mantener los **dos ESP32 conectados al teléfono simultáneamente**.
- Recibe el protocolo actual del guante:
  `10101,Pitch,Roll,Ax,Ay,Az,Gx,Gy,Gz`
- También acepta datos ya procesados:
  `VOICE: GRACIAS`
- Tiene modo alternativo para que un solo guante reenvíe las dos manos:
  `DUAL|<payload_izquierdo>|<payload_derecho>`
- También acepta:
  `{"left":"<payload>","right":"<payload>"}`
- Terminal BLE en tiempo real.
- Entrenamiento de nuevas palabras con **10 grabaciones**, cada una confirmada con el botón **Listo**.
- Reconocimiento local en el teléfono mediante distancia al centroide de las muestras.
- Texto y voz.
- 6 idiomas: **español, inglés, chino, francés, portugués y alemán**.
- Las palabras entrenadas se guardan localmente en el teléfono.

## Compilar automáticamente con GitHub

1. Crea un repositorio nuevo en GitHub.
2. Sube **todo el contenido** de este proyecto.
3. Ve a **Actions**.
4. Abre `Build Android APK`.
5. Pulsa `Run workflow`.
6. Al terminar, entra en la ejecución y descarga el artifact:
   `Guante-De-Voz-APK`.
7. Dentro estará `app-release.apk`.

El workflow genera automáticamente la carpeta Android, instala Flutter y compila el APK.

## Protocolo del firmware izquierdo actual

El código proporcionado envía aproximadamente a 30 Hz:

```
fingerBits,pitch,roll,ax,ay,az,gx,gy,gz
```

Ejemplo:

```
10101,-12.3,5.7,0.10,-9.70,1.22,0.1,-0.2,0.0
```

El guante derecho debe usar el mismo Service UUID y Characteristic UUID, pero anunciarse como:

```cpp
#define DEVICE_NAME "SmartGlove_Right"
```

El teléfono distingue cada mano por el dispositivo BLE al que está conectado.

## Alternativa: un ESP32 envía las dos manos

Si más adelante decides que el izquierdo envía sus datos al derecho por ESP-NOW/BLE/otro enlace, el derecho puede notificar al teléfono así:

```
DUAL|10101,-12.3,5.7,0.10,-9.70,1.22,0.1,-0.2,0.0|01011,6.2,-4.1,0.20,-9.60,0.80,0.2,0.0,-0.1
```

No hace falta modificar la app.

## Entrenamiento

1. Conecta los guantes.
2. Ve a `Entrenar`.
3. Escribe la palabra.
4. Opcional: escribe la traducción en los seis idiomas.
5. Realiza la seña.
6. Pulsa `Listo`.
7. Repite hasta llegar a `10/10`.
8. Pulsa `Guardar nueva palabra`.

Para cada muestra se usa una ventana reciente de datos de ambas manos. El modelo se almacena localmente.

## Nota importante sobre reconocimiento

El sistema de esta versión es un clasificador ligero por plantillas/centroides, diseñado para un prototipo escolar y para que puedas **agregar nuevas palabras directamente desde la app** sin reprogramar el ESP32. Para un vocabulario grande o señas dinámicas complejas, conviene sustituir `GestureMath` por un modelo temporal (por ejemplo TFLite) entrenado con secuencias completas.

## Archivos importantes

- `lib/ble_manager.dart`: conexión BLE y parser.
- `lib/models.dart`: datos y reconocimiento.
- `lib/main.dart`: interfaz.
- `lib/storage.dart`: palabras entrenadas.
- `tool/AndroidManifest.xml`: permisos Android BLE.
- `.github/workflows/build-apk.yml`: compilación automática del APK.
