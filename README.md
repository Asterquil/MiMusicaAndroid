# Mi Música 3.0 — Android / GitHub Actions

Basado en la versión 2.0 suministrada. Conserva la biblioteca MediaStore, filtros, playlists, reproducción y búsqueda local.

## Cambios
- Se añade búsqueda y streaming de pistas Jamendo mediante API oficial (requiere client_id).
- Descarga solo cuando `audiodownload_allowed` es `true`; los archivos se guardan en el almacenamiento privado de la app. Las licencias pueden exigir atribución y otras condiciones: comprueba los términos de Jamendo y de cada pista antes de redistribuir.
- Recupera última pista **local** y posición al volver a abrir la app, sin reproducción automática.
- Se configura el servicio multimedia `stopWithTask=false`, permiso INTERNET y POST_NOTIFICATIONS. El comportamiento real al quitar de recientes depende de Android/HiOS y del servicio; **no se ha probado en dispositivo**.
- Se conserva `just_audio_background`, sin reemplazar la arquitectura de reproducción. Los controles multimedia dependen de que Android active correctamente la sesión.

## Activar Jamendo
1. Solicita un `client_id` en https://developer.jamendo.com/ . Revisa condiciones de uso y licencias.
2. En GitHub: Settings → Secrets and variables → Actions → New repository secret.
3. Nombre: `JAMENDO_CLIENT_ID`; valor: tu identificador.
4. Ejecuta Actions → Compilar APK Android → Run workflow. Sin este secret, la biblioteca local funciona, pero la búsqueda en línea indica que falta configurar Jamendo.

## Subir cambios
Reemplaza en GitHub `lib/main.dart`, `pubspec.yaml`, `android_custom/configure_android.py`, `.github/workflows/android-apk.yml` y README.md. Conserva `android_custom/MainActivity.kt`.

## Advertencias
- **Sin compilación comprobada:** Flutter no está instalado en este entorno; GitHub Actions debe validar la compilación.
- El proceso de compilación actual usa firma automática de Flutter, no una clave de release estable; instalar sobre una versión previa puede fallar por diferencia de firma.
- El guardado de progreso es periódico (cada 5 s) y puede perder los últimos segundos si Android mata el proceso.
- El reproductor singleton mejora continuidad en el proceso, pero no garantiza reproducción si HiOS mata el proceso al retirar la app. Para máxima robustez se recomienda migrar a un AudioHandler de audio_service gestionado fuera del widget.
- El catálogo Jamendo no equivale al de Spotify; solo se pueden descargar pistas con autorización del proveedor y respetando su licencia.


## Versión 3.1 — correcciones en prueba

- Se eliminó el parámetro inválido `mainAxisSize` de `Wrap`.
- Se evita entregar una URI `content://` de portada al servicio de notificaciones (las portadas dentro de la app se mantienen).
- Se registran errores del reproductor y se intenta recuperar el avance solo si la cola llega a `completed` y quedan pistas.
- **No está verificado** que el servicio multimedia sobreviva 20 minutos en TECNO/HiOS ni que aparezca la notificación: requiere pruebas en dispositivo y, si falla, registros de Android (`adb logcat`).
- Jamendo: registrar un cliente en developer.jamendo.com y añadir el secreto `JAMENDO_CLIENT_ID` en GitHub Settings → Secrets and variables → Actions. Ejecutar de nuevo el workflow para compilar con el identificador. El `client_id` embebido en una APK no es un secreto real; consultar condiciones y cuotas de Jamendo.
- La versión mantiene el mismo `applicationId` generado por Flutter; para actualizar una APK existente se requiere la misma firma. Hacer copia de los datos antes de desinstalar.
