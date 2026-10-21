#!/usr/bin/env bash
# Gera o projeto Android do Flutter em volta do lib/main.dart e configura o som em segundo plano.
set -e
cp lib/main.dart /tmp/main.dart
flutter create --org com.renplay --project-name renplay --platforms android .
cp /tmp/main.dart lib/main.dart
rm -rf test
flutter pub add just_audio:^0.9.40 just_audio_background file_picker:^8.0.0 path_provider shared_preferences audio_metadata_reader
python3 - <<'PY'
import re, glob, pathlib
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = m.read_text()
perms = '''<uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    '''
svc = '''<service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback" android:exported="true">
            <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" android:exported="true">
            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
        </receiver>
    '''
s = s.replace('<application', perms + '<application', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Renplay"', s, 1)
s = s.replace('</application>', svc + '</application>', 1)
m.write_text(s)
for f in glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True):
    p = pathlib.Path(f)
    pkg = re.search(r'package\s+(\S+)', p.read_text()).group(1)
    p.write_text(f'package {pkg}\n\nimport com.ryanheise.audioservice.AudioServiceActivity\n\nclass MainActivity : AudioServiceActivity()\n')
PY
