package com.marketvendor.market_vendor_app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream

class FileStoragePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.marketvendor.market_vendor_app/file_storage")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "saveFile" -> {
                val content = call.argument<String>("content")
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType") ?: "text/plain"

                if (content == null || fileName == null) {
                    result.error("INVALID_ARGUMENTS", "Content or fileName is null", null)
                    return
                }

                try {
                    val filePath = saveFile(content, fileName, mimeType)
                    result.success(filePath)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", "Failed to save file: ${e.message}", null)
                }
            }
            "saveBytes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                if (bytes == null || fileName == null) {
                    result.error("INVALID_ARGUMENTS", "Bytes or fileName is null", null)
                    return
                }

                try {
                    val filePath = saveBytes(bytes, fileName, mimeType)
                    result.success(filePath)
                } catch (e: Exception) {
                    result.error("SAVE_FAILED", "Failed to save file: ${e.message}", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun saveFile(content: String, fileName: String, mimeType: String): String {
        // Sử dụng MediaStore API cho Android 10 (Q) trở lên
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }

            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw IOException("Failed to create new MediaStore record")

            context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                outputStream.write(content.toByteArray())
            } ?: throw IOException("Failed to open output stream")

            // Trả về đường dẫn hiển thị cho người dùng
            return "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)}/$fileName"
        } 
        // Sử dụng cách truyền thống cho Android 9 (Pie) trở xuống
        else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }

            val file = File(downloadsDir, fileName)
            FileOutputStream(file).use { outputStream ->
                outputStream.write(content.toByteArray())
            }
            return file.absolutePath
        }
    }

    private fun saveBytes(bytes: ByteArray, fileName: String, mimeType: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }

            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw IOException("Failed to create new MediaStore record")

            context.contentResolver.openOutputStream(uri)?.use { outputStream: OutputStream ->
                outputStream.write(bytes)
            } ?: throw IOException("Failed to open output stream")

            return "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)}/$fileName"
        } else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }

            val file = File(downloadsDir, fileName)
            FileOutputStream(file).use { outputStream ->
                outputStream.write(bytes)
            }
            return file.absolutePath
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}