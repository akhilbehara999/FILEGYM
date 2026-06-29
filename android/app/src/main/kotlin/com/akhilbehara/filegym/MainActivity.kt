package com.akhilbehara.filegym

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.MediaScannerConnection
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.akhilbehara.filegym/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(
                        context,
                        arrayOf(path),
                        null
                    ) { _, _ -> }
                    result.success(true)
                } else {
                    result.error("INVALID_PATH", "Path was null", null)
                }
            } else if (call.method == "renderPdfPage") {
                val pdfPath = call.argument<String>("pdfPath")
                val outputPath = call.argument<String>("outputPath")
                val pageIndex = call.argument<Int>("pageIndex") ?: 0
                
                if (pdfPath != null && outputPath != null) {
                    thread {
                        try {
                            val file = File(pdfPath)
                            val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            val renderer = PdfRenderer(fd)
                            
                            if (pageIndex < renderer.pageCount) {
                                val page = renderer.openPage(pageIndex)
                                
                                val width = page.width * 3
                                val height = page.height * 3
                                
                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                bitmap.eraseColor(Color.WHITE)
                                
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                page.close()
                                
                                val outFile = File(outputPath)
                                val outStream = FileOutputStream(outFile)
                                
                                val ext = outFile.extension.lowercase()
                                val format = if (ext == "png") Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
                                bitmap.compress(format, 80, outStream)
                                outStream.flush()
                                outStream.close()
                                
                                renderer.close()
                                fd.close()
                                runOnUiThread {
                                    result.success(true)
                                }
                            } else {
                                renderer.close()
                                fd.close()
                                runOnUiThread {
                                    result.error("INVALID_PAGE", "Page index out of bounds", null)
                                }
                            }
                        } catch (e: Throwable) {
                            runOnUiThread {
                                result.error("RENDER_FAILED", e.message, null)
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                }
            } else if (call.method == "getPdfPageCount") {
                val pdfPath = call.argument<String>("pdfPath")
                if (pdfPath != null) {
                    try {
                        val file = File(pdfPath)
                        val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                        val renderer = PdfRenderer(fd)
                        val count = renderer.pageCount
                        renderer.close()
                        fd.close()
                        result.success(count)
                    } catch (e: Throwable) {
                        result.error("PAGE_COUNT_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing pdfPath argument", null)
                }
            } else if (call.method == "convertHeic") {
                val heicPath = call.argument<String>("heicPath")
                val outputPath = call.argument<String>("outputPath")
                
                if (heicPath != null && outputPath != null) {
                    thread {
                        try {
                            val bitmap = android.graphics.BitmapFactory.decodeFile(heicPath)
                            if (bitmap != null) {
                                val outFile = File(outputPath)
                                val outStream = FileOutputStream(outFile)
                                val ext = outFile.extension.lowercase()
                                val format = if (ext == "png") Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG
                                bitmap.compress(format, 90, outStream)
                                outStream.flush()
                                outStream.close()
                                bitmap.recycle()
                                runOnUiThread {
                                    result.success(true)
                                }
                            } else {
                                runOnUiThread {
                                    result.error("DECODE_FAILED", "Failed to decode HEIC bitmap", null)
                                }
                            }
                        } catch (e: Throwable) {
                            runOnUiThread {
                                result.error("CONVERSION_FAILED", e.message, null)
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                }
            } else if (call.method == "resizeImage") {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val quality = call.argument<Int>("quality") ?: 80
                
                if (sourcePath != null && outputPath != null && width != null && height != null) {
                    thread {
                        try {
                            val srcBitmap = android.graphics.BitmapFactory.decodeFile(sourcePath)
                            if (srcBitmap != null) {
                                val scaledBitmap = Bitmap.createScaledBitmap(srcBitmap, width, height, true)
                                val outFile = File(outputPath)
                                val outStream = FileOutputStream(outFile)
                                val ext = outFile.extension.lowercase()
                                val format = if (ext == "png") {
                                    Bitmap.CompressFormat.PNG
                                } else if (ext == "webp") {
                                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                        Bitmap.CompressFormat.WEBP_LOSSY
                                    } else {
                                        @Suppress("DEPRECATION")
                                        Bitmap.CompressFormat.WEBP
                                    }
                                } else {
                                    Bitmap.CompressFormat.JPEG
                                }
                                scaledBitmap.compress(format, quality, outStream)
                                outStream.flush()
                                outStream.close()
                                
                                if (scaledBitmap != srcBitmap) {
                                    scaledBitmap.recycle()
                                }
                                srcBitmap.recycle()
                                runOnUiThread {
                                    result.success(true)
                                }
                            } else {
                                runOnUiThread {
                                    result.error("DECODE_FAILED", "Failed to decode source image", null)
                                }
                            }
                        } catch (e: Throwable) {
                            runOnUiThread {
                                result.error("RESIZE_FAILED", e.message, null)
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
