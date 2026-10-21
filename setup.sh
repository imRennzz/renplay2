#!/usr/bin/env bash
# Gera o projeto Android do Flutter em volta do lib/main.dart e configura o som em segundo plano.
set -e
cp lib/main.dart /tmp/main.dart
flutter create --org com.renplay --project-name renplay --platforms android .
cp /tmp/main.dart lib/main.dart
rm -rf test
flutter pub add just_audio:^0.9.40 just_audio_background file_picker:^8.0.0 path_provider shared_preferences audio_metadata_reader
python3 - <<'PY'
import re, glob, os, pathlib
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = m.read_text()
perms = '''<uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
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

kt = '''package PKG

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        } else {
            askBattery()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1) askBattery()
    }

    private fun askBattery() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val prefs = getSharedPreferences("renplay", Context.MODE_PRIVATE)
            if (!pm.isIgnoringBatteryOptimizations(packageName) && !prefs.getBoolean("asked", false)) {
                prefs.edit().putBoolean("asked", true).apply()
                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + packageName)))
            }
        } catch (e: Exception) {
        }
    }
}
'''
for f in glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True):
    p = pathlib.Path(f)
    pkg = re.search(r'package\s+(\S+)', p.read_text()).group(1)
    p.write_text(kt.replace('PKG', pkg))

# Força todos os módulos a compilar com Android SDK 36
kts = pathlib.Path('android/build.gradle.kts')
gr = pathlib.Path('android/build.gradle')
if kts.exists():
    kts.write_text('''subprojects {
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.compileSdkVersion(36)
    }
}

''' + kts.read_text())
elif gr.exists():
    gr.write_text('''subprojects {
    afterEvaluate { p ->
        if (p.hasProperty('android')) { p.android { compileSdkVersion 36 } }
    }
}

''' + gr.read_text())
PY
