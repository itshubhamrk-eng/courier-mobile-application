package com.softech.branch_ops

import android.net.Uri
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "branch_ops/text_reader")
            .setMethodCallHandler { call, result ->
                val path = call.argument<String>("path")
                when {
                    call.method != "read" -> result.notImplemented()
                    path == null -> result.error("bad_image", "No photo", null)
                    else -> readText(path, result)
                }
            }
    }

    /** Reads a photo on the device: English first, Hindi / Marathi when that script is present. */
    private fun readText(path: String, result: MethodChannel.Result) {
        val image = try {
            InputImage.fromFilePath(this, Uri.fromFile(File(path)))
        } catch (e: Exception) {
            result.error("bad_image", e.message, null)
            return
        }
        val latin = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val devanagari = TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
        run(latin, image) { english, error ->
            run(devanagari, image) { hindi, _ ->
                val indic = hindi?.text?.count { it in 'ऀ'..'ॿ' } ?: 0
                val best = if (hindi != null && (english == null || indic >= 10)) hindi else english
                when {
                    best != null -> result.success(lines(best))
                    (error as? MlKitException)?.errorCode == MlKitException.UNAVAILABLE ->
                        result.error("not_ready", error.message, null)
                    else -> result.error("failed", error?.message, null)
                }
            }
        }
    }

    private fun run(client: TextRecognizer, image: InputImage, done: (Text?, Exception?) -> Unit) {
        client.process(image).addOnCompleteListener { task ->
            client.close()
            if (task.isSuccessful) done(task.result, null) else done(null, task.exception)
        }
    }

    private fun lines(text: Text): List<Map<String, Any>> =
        text.textBlocks.flatMap { it.lines }.map { line ->
            val box = line.boundingBox
            mapOf(
                "text" to line.text,
                "left" to (box?.left ?: 0),
                "top" to (box?.top ?: 0),
                "right" to (box?.right ?: 0),
                "bottom" to (box?.bottom ?: 0),
            )
        }
}
