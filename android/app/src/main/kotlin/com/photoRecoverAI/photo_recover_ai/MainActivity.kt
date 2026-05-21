package com.photoRecoverAI.photo_recover_ai

import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val mediaStoreChannel = "photo_recover_ai/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanAccessibleMedia" -> handleScanAccessibleMedia(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleScanAccessibleMedia(call: MethodCall, result: MethodChannel.Result) {
        val fileType = (call.argument<String>("fileType") ?: "photo").lowercase(Locale.US)
        val deletedOnly = call.argument<Boolean>("deletedOnly") ?: false

        try {
            val payload = queryMediaStore(fileType = fileType, deletedOnly = deletedOnly)
            result.success(payload)
        } catch (t: Throwable) {
            result.error("MEDIASTORE_SCAN_ERROR", t.message, null)
        }
    }

    private fun queryMediaStore(fileType: String, deletedOnly: Boolean): Map<String, Any> {
        val resolver = contentResolver
        val uri = uriForType(fileType)
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.MIME_TYPE
        ).apply {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                add(MediaStore.MediaColumns.DATA)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                add(MediaStore.MediaColumns.IS_TRASHED)
            }
        }.toTypedArray()

        val selectionParts = mutableListOf<String>()
        val args = mutableListOf<String>()

        if (fileType == "file") {
            selectionParts.add(
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_NONE}"
            )
        }

        if (deletedOnly) {
            val pathLike =
                "(lower(${MediaStore.MediaColumns.RELATIVE_PATH}) LIKE ? OR lower(${MediaStore.MediaColumns.DISPLAY_NAME}) LIKE ?)"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                selectionParts.add("(${MediaStore.MediaColumns.IS_TRASHED} = 1 OR $pathLike)")
            } else {
                selectionParts.add(pathLike)
            }
            args.add("%trash%")
            args.add("%deleted%")
        }

        val selection = if (selectionParts.isEmpty()) null else selectionParts.joinToString(" AND ")
        val selectionArgs = if (args.isEmpty()) null else args.toTypedArray()
        val sortOrder = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"

        val files = mutableListOf<Map<String, Any?>>()
        var scannedCount = 0

        resolver.query(uri, projection, selection, selectionArgs, sortOrder)?.use { cursor ->
            scannedCount = cursor.count

            val idIdx = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
            val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeIdx = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
            val modifiedIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
            val relativePathIdx = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            val dataIdx = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
            } else {
                -1
            }
            val trashedIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED)
            } else {
                -1
            }

            while (cursor.moveToNext()) {
                val id = if (idIdx >= 0) cursor.getLong(idIdx) else 0L
                val name = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else ""
                if (name.isBlank()) continue

                val size = if (sizeIdx >= 0) cursor.getLong(sizeIdx) else 0L
                val modifiedSec = if (modifiedIdx >= 0) cursor.getLong(modifiedIdx) else 0L
                val modifiedMs = modifiedSec * 1000L
                val relativePath = if (relativePathIdx >= 0) cursor.getString(relativePathIdx) ?: "" else ""
                val dataPath = if (dataIdx >= 0) cursor.getString(dataIdx) else null

                val fullPath = buildAbsolutePath(relativePath = relativePath, name = name, dataPath = dataPath)
                if (fullPath.isBlank()) continue

                val isTrashed = trashedIdx >= 0 && cursor.getInt(trashedIdx) == 1
                val source = classifySource(fullPath, relativePath, isTrashed)
                val qualityTag = qualityTagForPath(fullPath, source)

                if (deletedOnly && !isLikelyDeletedTrace(fullPath, relativePath, isTrashed)) {
                    continue
                }

                files.add(
                    mapOf(
                        "id" to id.toString(),
                        "name" to name,
                        "path" to fullPath,
                        "extension" to extensionOf(name),
                        "size" to size,
                        "lastModifiedMs" to modifiedMs,
                        "source" to source,
                        "qualityTag" to qualityTag
                    )
                )
            }
        }

        return mapOf(
            "scannedCount" to scannedCount,
            "files" to files
        )
    }

    private fun uriForType(fileType: String): Uri {
        return when (fileType) {
            "photo" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            "file" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Files.getContentUri("external")
            }
            else -> MediaStore.Files.getContentUri("external")
        }
    }

    private fun buildAbsolutePath(relativePath: String, name: String, dataPath: String?): String {
        if (!dataPath.isNullOrBlank()) return dataPath
        if (relativePath.isBlank()) return ""
        val cleanRelative = relativePath.trimStart('/')
        val normalizedRelative = if (cleanRelative.endsWith("/")) cleanRelative else "$cleanRelative/"
        return "/storage/emulated/0/$normalizedRelative$name"
    }

    private fun extensionOf(name: String): String {
        val idx = name.lastIndexOf('.')
        if (idx < 0 || idx >= name.length - 1) return ""
        return name.substring(idx).lowercase(Locale.US)
    }

    private fun classifySource(path: String, relativePath: String, isTrashed: Boolean): String {
        val rel = relativePath.lowercase(Locale.US)
        val p = path.lowercase(Locale.US)

        if (isTrashed || rel.contains("trash") || rel.contains("recycle") || rel.contains("deleted")) {
            return "Recently Deleted"
        }
        if (rel.contains(".thumbnails") || rel.contains("/cache/") || rel.contains("thumbnail")) {
            return "Cache"
        }
        if (rel.contains("whatsapp") || rel.contains("messenger") || rel.contains("telegram") || rel.contains("instagram")) {
            return "Messenger"
        }
        if (rel.contains("dcim") || rel.contains("camera")) return "DCIM"
        if (rel.contains("pictures")) return "Pictures"
        if (rel.contains("download")) return "Downloads"
        if (rel.contains("android/media")) return "Android Media"
        if (p.contains("/android/media/")) return "Android Media"
        return "Accessible Media"
    }

    private fun qualityTagForPath(path: String, source: String): String? {
        val lower = path.lowercase(Locale.US)
        if (source == "Cache" || lower.contains(".thumbnails") || lower.contains("thumb")) {
            return "thumbnail"
        }
        if (source == "Recently Deleted") {
            return "recovered"
        }
        return null
    }

    private fun isLikelyDeletedTrace(path: String, relativePath: String, isTrashed: Boolean): Boolean {
        if (isTrashed) return true

        val rel = relativePath.lowercase(Locale.US)
        val p = path.lowercase(Locale.US)
        if (rel.contains("trash") || rel.contains("recycle") || rel.contains("deleted")) return true
        if (rel.contains(".thumbnails") || rel.contains("/cache/") || rel.contains("cache")) return true
        if (p.contains("/android/media/") && (p.contains("trash") || p.contains("deleted"))) return true

        val file = File(path)
        if (file.name.lowercase(Locale.US).contains("deleted")) return true
        return false
    }
}
