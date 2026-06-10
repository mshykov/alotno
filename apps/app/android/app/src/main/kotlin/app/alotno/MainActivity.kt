package app.alotno

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Receives PNGs shared/opened into the app (ACTION_SEND / SEND_MULTIPLE /
/// VIEW — see the intent-filters in AndroidManifest.xml) and pushes readable
/// file paths to Dart over the "app.alotno/incoming" channel
/// (lib/mobile/incoming_files.dart). content:// streams are copied into
/// cacheDir first so Dart gets plain paths.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val pending = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.alotno/incoming",
        ).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "getInitialFiles") {
                    result.success(pending.toList())
                    pending.clear()
                } else {
                    result.notImplemented()
                }
            }
        }
        intent?.let { handleIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> streamExtra(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> streamExtras(intent)?.let { uris.addAll(it) }
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            else -> return
        }
        val paths = uris.mapNotNull { copyToCache(it) }
        if (paths.isEmpty()) return
        channel?.invokeMethod("openFiles", paths) ?: pending.addAll(paths)
    }

    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    private fun streamExtras(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }

    private fun copyToCache(uri: Uri): String? = try {
        contentResolver.openInputStream(uri)?.use { input ->
            val file = File.createTempFile("shared_", ".png", cacheDir)
            file.outputStream().use { input.copyTo(it) }
            file.absolutePath
        }
    } catch (_: Exception) {
        null
    }
}
