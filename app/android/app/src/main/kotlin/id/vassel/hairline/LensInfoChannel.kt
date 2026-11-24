// Copyright (c) 2026 Vassel Goleyu. MIT License.
package id.vassel.hairline

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reads lens facts for the intrinsics approximation (CLAUDE.md 5.2): focal length, physical
 * sensor size, pixel array, sensor orientation. Missing characteristics are simply left
 * out of the reply; the Dart side then falls back to its defaults. No permission needed.
 */
class LensInfoChannel(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "id.vassel.hairline/lens"

        fun register(messenger: BinaryMessenger, context: Context) {
            MethodChannel(messenger, NAME).setMethodCallHandler(LensInfoChannel(context))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "getLensInfo") {
            result.notImplemented()
            return
        }
        val cameraId = call.argument<String>("cameraId")
        if (cameraId == null) {
            result.error("ARGUMENT", "cameraId is required", null)
            return
        }
        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val c = manager.getCameraCharacteristics(cameraId)
            val reply = HashMap<String, Any>()
            reply["cameraId"] = cameraId
            reply["deviceModel"] = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
            c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull()?.let {
                reply["focalLengthMm"] = it.toDouble()
            }
            c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)?.let {
                reply["sensorWidthMm"] = it.width.toDouble()
                reply["sensorHeightMm"] = it.height.toDouble()
            }
            c.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)?.let {
                reply["pixelArrayWidth"] = it.width
                reply["pixelArrayHeight"] = it.height
            }
            c.get(CameraCharacteristics.SENSOR_ORIENTATION)?.let { reply["sensorOrientation"] = it }
            result.success(reply)
        } catch (e: Exception) {
            // Unknown id, camera service unavailable, ...: the Dart side treats this as "no lens info".
            result.error("LENS_INFO", e.message, null)
        }
    }
}
