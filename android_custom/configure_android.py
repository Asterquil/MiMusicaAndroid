from pathlib import Path
import re
root=Path('android')
app=root/'app'
manifest=app/'src/main/AndroidManifest.xml'
s=manifest.read_text()
s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />''')
s=s.replace('<application', '<application',1)
s=s.replace('android:label="music_player_local"','android:label="Mi Música"')
service='''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:stopWithTask="false"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
'''
s=s.replace('</application>',service+'</application>')
manifest.write_text(s)
# Compile SDK 36 for modern AndroidX plugins; target SDK stays Flutter's default.
for name in ('build.gradle.kts','build.gradle'):
    p=app/name
    if p.exists():
        t=p.read_text()
        t=re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion','compileSdk = 36',t)
        t=re.sub(r'compileSdkVersion\s+flutter\.compileSdkVersion','compileSdkVersion 36',t)
        p.write_text(t)
# Kotlin source under the package produced by flutter create --org com.mimusica
p=app/'src/main/kotlin/com/mimusica/music_player_local/MainActivity.kt'
p.parent.mkdir(parents=True,exist_ok=True)
p.write_text(Path('android_custom/MainActivity.kt').read_text())
print('Android manifest, compileSdk and MainActivity configured')
