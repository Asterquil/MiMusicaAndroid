# Mi Música — proyecto listo para GitHub Actions

Aplicación Flutter para Android que reproduce música local. Incluye búsqueda, playlists, metadatos, portadas cuando estén disponibles, controles de reproducción, volumen, progreso, aleatorio y repetición.

## Subir a GitHub (sin instalar Flutter)

1. Crea un repositorio **nuevo y vacío** en https://github.com/new con nombre `MiMusicaAndroid` y rama `main`.
2. Extrae el ZIP descargado en tu PC. **No subas el ZIP sin extraer.**
3. En GitHub, entra en el repositorio y usa **Add file → Upload files**. Sube `lib/main.dart`, `pubspec.yaml`, `README.md` y `.gitignore`. GitHub puede no incluir carpetas ocultas al arrastrarlas: **asegúrate de subir también `.github/workflows/android-apk.yml`** con su ruta exacta. Una opción fiable es subir la carpeta entera con Git desde el PC.
4. Confirma los archivos con **Commit changes**.
5. Abre **Actions → Compilar APK Android**. Si no comienza solo, pulsa **Run workflow**.
6. Al finalizar correctamente, abre la ejecución y descarga el artefacto **MiMusica-Android-APK** desde la sección **Artifacts**. Descomprime el ZIP de artefactos para obtener `app-release.apk`.
7. Copia el APK a tu teléfono e instálalo. Android puede solicitar autorización para instalar aplicaciones de esa fuente.

**Nota:** La automatización genera la estructura `android/` durante la compilación; no hace falta subirla. Este flujo no publica en Google Play ni genera un enlace de descarga permanente. El APK se firma con la clave de depuración/por defecto del entorno de compilación de Flutter, no con una clave de publicación gestionada por ti; para distribuir actualizaciones estables o publicar en Play Store necesitarás configurar tu firma de lanzamiento.

**Estado:** Código y flujo preparados, pero no compilados ni verificados en GitHub en este entorno. Si GitHub muestra un error en Actions, comparte el registro para corregirlo.
