package com.mimusica.music_player_local

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val channelName = "mimusica/library"
    private val requestCode = 8842
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> requestAudioPermission(result)
                "songs" -> result.success(readSongs())
                "art" -> {
                    val albumId = call.argument<Number>("albumId")?.toLong()
                    if (albumId == null) { result.success(null); return@setMethodCallHandler }
                    try {
                        val uri = ContentUris.withAppendedId(android.net.Uri.parse("content://media/external/audio/albumart"), albumId)
                        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        result.success(bytes)
                    } catch (_: Exception) { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun audioPermission(): String = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, audioPermission()) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
        } else if (pendingPermission != null) {
            result.error("BUSY", "Permission request already running", null)
        } else {
            pendingPermission = result
            ActivityCompat.requestPermissions(this, arrayOf(audioPermission()), requestCode)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == this.requestCode) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    private fun readSongs(): List<Map<String, Any?>> {
        if (ContextCompat.checkSelfPermission(this, audioPermission()) != PackageManager.PERMISSION_GRANTED) return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE, MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM, MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.RELATIVE_PATH, MediaStore.Audio.Media.IS_MUSIC
        )
        val excluded = listOf("whatsapp", "voice", "record", "grabacion", "grabación", "telegram", "notifications", "ringtones", "alarms", "podcast")
        try {
            contentResolver.query(uri, projection, "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= ?", arrayOf("30000"), "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC")?.use { cursor ->
                fun str(column: String): String = cursor.getString(cursor.getColumnIndexOrThrow(column)) ?: ""
                fun num(column: String): Long = cursor.getLong(cursor.getColumnIndexOrThrow(column))
                while (cursor.moveToNext()) {
                    val folder = str(MediaStore.Audio.Media.RELATIVE_PATH).lowercase()
                    val filename = str(MediaStore.Audio.Media.DISPLAY_NAME).lowercase()
                    if (excluded.any { folder.contains(it) } || filename.startsWith("ptt-") || filename.startsWith("aud-") || filename.startsWith("voice-")) continue
                    val id = num(MediaStore.Audio.Media._ID)
                    results.add(mapOf(
                        "id" to id.toString(),
                        "uri" to ContentUris.withAppendedId(uri, id).toString(),
                        "title" to str(MediaStore.Audio.Media.TITLE).ifBlank { str(MediaStore.Audio.Media.DISPLAY_NAME) },
                        "artist" to str(MediaStore.Audio.Media.ARTIST),
                        "album" to str(MediaStore.Audio.Media.ALBUM),
                        "albumId" to num(MediaStore.Audio.Media.ALBUM_ID),
                        "duration" to num(MediaStore.Audio.Media.DURATION)
                    ))
                }
            }
        } catch (_: Exception) { return emptyList() }
        return results
    }
}
