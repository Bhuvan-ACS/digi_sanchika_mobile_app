package com.digisanchika.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.WindowManager
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
  private val mediaPickerChannel = "digi_sanchika/media_picker"
  private val mediaPickerRequestCode = 42017
  private var pendingPickerResult: MethodChannel.Result? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // Ensure screenshots/screen recording are allowed (debug/dev builds).
    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaPickerChannel)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "pickMedia" -> {
            if (pendingPickerResult != null) {
              result.error("picker_active", "A media picker is already active.", null)
              return@setMethodCallHandler
            }

            val mediaType = call.argument<String>("mediaType") ?: "image"
            val allowMultiple = call.argument<Boolean>("allowMultiple") ?: false
            pendingPickerResult = result
            openMediaPicker(mediaType, allowMultiple)
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun openMediaPicker(mediaType: String, allowMultiple: Boolean) {
    val mimeType = if (mediaType == "video") "video/*" else "image/*"
    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      Intent(MediaStore.ACTION_PICK_IMAGES).apply {
        type = mimeType
        if (allowMultiple) {
          putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
          putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit())
        }
      }
    } else {
      Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = mimeType
        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
      }
    }

    try {
      startActivityForResult(intent, mediaPickerRequestCode)
    } catch (e: Exception) {
      pendingPickerResult?.error("picker_unavailable", e.message, null)
      pendingPickerResult = null
    }
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)

    if (requestCode != mediaPickerRequestCode) return

    val result = pendingPickerResult ?: return
    pendingPickerResult = null

    if (resultCode != Activity.RESULT_OK || data == null) {
      result.success(emptyList<Map<String, Any?>>())
      return
    }

    try {
      val uris = collectSelectedUris(data)
      val files = uris.mapIndexed { index, uri -> copyUriToCache(uri, index) }
      result.success(files)
    } catch (e: Exception) {
      result.error("picker_copy_failed", e.message, null)
    }
  }

  private fun collectSelectedUris(data: Intent): List<Uri> {
    val selected = mutableListOf<Uri>()
    val clipData = data.clipData
    if (clipData != null) {
      for (i in 0 until clipData.itemCount) {
        selected.add(clipData.getItemAt(i).uri)
      }
    } else {
      data.data?.let { selected.add(it) }
    }
    return selected
  }

  private fun copyUriToCache(uri: Uri, index: Int): Map<String, Any?> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      try {
        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
      } catch (_: Exception) {
        // Some providers grant only temporary access; copying immediately is enough for upload.
      }
    }

    val displayName = queryDisplayName(uri) ?: "media_${System.currentTimeMillis()}_$index"
    val safeName = sanitizeFileName(displayName)
    val extension = safeName.substringAfterLast('.', missingDelimiterValue = "")
      .ifBlank { extensionFromMime(uri) }
    val finalName = if (safeName.contains('.')) safeName else "$safeName.$extension"
    val outFile = File(cacheDir, "picked_${System.currentTimeMillis()}_${index}_$finalName")

    contentResolver.openInputStream(uri).use { input ->
      requireNotNull(input) { "Unable to open selected media." }
      FileOutputStream(outFile).use { output -> input.copyTo(output) }
    }

    return mapOf(
      "name" to finalName,
      "path" to outFile.absolutePath,
      "size" to outFile.length(),
      "extension" to outFile.extension
    )
  }

  private fun queryDisplayName(uri: Uri): String? {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null).use { cursor ->
      if (cursor != null && cursor.moveToFirst()) {
        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (index >= 0) return cursor.getString(index)
      }
    }
    return null
  }

  private fun extensionFromMime(uri: Uri): String {
    val mime = contentResolver.getType(uri)
    return MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "bin"
  }

  private fun sanitizeFileName(name: String): String =
    name.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "selected_media" }
}