package com.example.mangashelf

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "mangashelf/file_open"

    private var methodChannel: MethodChannel? = null
    private var pendingFile: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    result.success(pendingFile)
                    pendingFile = null
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, notifyFlutter = true)
    }

    private fun handleIncomingIntent(
        intent: Intent?,
        notifyFlutter: Boolean
    ) {
        if (intent?.action != Intent.ACTION_VIEW) {
            return
        }

        val uri = intent.data ?: return

        try {
            val fileInfo = copyUriToAppCache(uri)

            if (notifyFlutter && methodChannel != null) {
                methodChannel?.invokeMethod(
                    "openFile",
                    fileInfo
                )
            } else {
                pendingFile = fileInfo
            }
        } catch (_: Exception) {
            // O Flutter continuará abrindo normalmente mesmo
            // se o arquivo recebido for inválido/inacessível.
        }
    }

    private fun copyUriToAppCache(
        uri: Uri
    ): Map<String, String> {
        val displayName =
            queryDisplayName(uri)
                ?: uri.lastPathSegment
                ?: "manga.epub"

        val safeName = displayName
            .replace(Regex("[^A-Za-z0-9._()\\- !]+"), "_")
            .takeLast(180)

        val incomingDir =
            File(cacheDir, "incoming_manga")

        if (!incomingDir.exists()) {
            incomingDir.mkdirs()
        }

        val outputFile = File(
            incomingDir,
            "${System.currentTimeMillis()}_$safeName"
        )

        contentResolver
            .openInputStream(uri)
            ?.use { input ->
                outputFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            ?: throw IllegalStateException(
                "Não foi possível ler o arquivo."
            )

        return mapOf(
            "path" to outputFile.absolutePath,
            "name" to displayName
        )
    }

    private fun queryDisplayName(
        uri: Uri
    ): String? {
        if (uri.scheme != "content") {
            return uri.lastPathSegment
        }

        return contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            val index = cursor.getColumnIndex(
                OpenableColumns.DISPLAY_NAME
            )

            if (index >= 0 && cursor.moveToFirst()) {
                cursor.getString(index)
            } else {
                null
            }
        }
    }
}
