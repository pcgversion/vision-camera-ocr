package com.visioncameraocr

import android.annotation.SuppressLint
import android.graphics.Point
import android.graphics.Rect
import android.media.Image
import androidx.camera.core.ImageProxy
import com.facebook.react.bridge.WritableNativeArray
import com.facebook.react.bridge.WritableNativeMap
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.mrousavy.camera.frameprocessor.FrameProcessorPlugin
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream
import android.graphics.Matrix

// OpenCV imports for image brightness and sharpness
import org.opencv.android.Utils
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.imgproc.Imgproc
import android.util.Log
import org.opencv.core.MatOfDouble
import org.opencv.android.OpenCVLoader
import org.opencv.core.Scalar
import org.opencv.core.Core
import org.opencv.core.Size


class OCRFrameProcessorPlugin: FrameProcessorPlugin("scanOCR") {

    companion object {
        init {
            if (OpenCVLoader.initDebug()) {
                Log.d("OpenCV", "OpenCV library loaded successfully")
            } else {
                Log.e("OpenCV", "Failed to load OpenCV library")
            }
        }
    }

    private fun getBlockArray(blocks: MutableList<Text.TextBlock>): WritableNativeArray {
        val blockArray = WritableNativeArray()

        for (block in blocks) {
            val blockMap = WritableNativeMap()

            blockMap.putString("text", block.text)
            blockMap.putArray("recognizedLanguages", getRecognizedLanguages(block.recognizedLanguage))
            blockMap.putArray("cornerPoints", block.cornerPoints?.let { getCornerPoints(it) })
            blockMap.putMap("frame", getFrame(block.boundingBox))
            blockMap.putArray("lines", getLineArray(block.lines))

            blockArray.pushMap(blockMap)
        }
        return blockArray
    }

    private fun getLineArray(lines: MutableList<Text.Line>): WritableNativeArray {
        val lineArray = WritableNativeArray()

        for (line in lines) {
            val lineMap = WritableNativeMap()

            lineMap.putString("text", line.text)
            lineMap.putArray("recognizedLanguages", getRecognizedLanguages(line.recognizedLanguage))
            lineMap.putArray("cornerPoints", line.cornerPoints?.let { getCornerPoints(it) })
            lineMap.putMap("frame", getFrame(line.boundingBox))
            lineMap.putArray("elements", getElementArray(line.elements))
            lineMap.putDouble("confidence", line.confidence.toDouble())
            lineMap.putDouble("angle", line.angle.toDouble())

            lineArray.pushMap(lineMap)
        }
        return lineArray
    }

    private fun getElementArray(elements: MutableList<Text.Element>): WritableNativeArray {
        val elementArray = WritableNativeArray()

        for (element in elements) {
            val elementMap = WritableNativeMap()

            elementMap.putString("text", element.text)
            elementMap.putArray("cornerPoints", element.cornerPoints?.let { getCornerPoints(it) })
            elementMap.putMap("frame", getFrame(element.boundingBox))
        }
        return elementArray
    }

    private fun getRecognizedLanguages(recognizedLanguage: String): WritableNativeArray {
        val recognizedLanguages = WritableNativeArray()
        recognizedLanguages.pushString(recognizedLanguage)
        return recognizedLanguages
    }

    private fun getCornerPoints(points: Array<Point>): WritableNativeArray {
        val cornerPoints = WritableNativeArray()

        for (point in points) {
            val pointMap = WritableNativeMap()
            pointMap.putInt("x", point.x)
            pointMap.putInt("y", point.y)
            cornerPoints.pushMap(pointMap)
        }
        return cornerPoints
    }

    private fun getFrame(boundingBox: Rect?): WritableNativeMap {
        val frame = WritableNativeMap()

        if (boundingBox != null) {
            frame.putDouble("x", boundingBox.exactCenterX().toDouble())
            frame.putDouble("y", boundingBox.exactCenterY().toDouble())
            frame.putInt("width", boundingBox.width())
            frame.putInt("height", boundingBox.height())
            frame.putInt("boundingCenterX", boundingBox.centerX())
            frame.putInt("boundingCenterY", boundingBox.centerY())
        }
        return frame
    }

    /*override fun callback(frame: ImageProxy, params: Array<Any>): Any? {

        val result = WritableNativeMap()

        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        @SuppressLint("UnsafeOptInUsageError")
        val mediaImage: Image? = frame.getImage()

        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, frame.imageInfo.rotationDegrees)
            val task: Task<Text> = recognizer.process(image)
            try {
                val text: Text = Tasks.await<Text>(task)
                result.putString("text", text.text)
                result.putArray("blocks", getBlockArray(text.textBlocks))
            } catch (e: Exception) {
                return null
            }
        }

        val data = WritableNativeMap()
        data.putMap("result", result)
        return data
    }*/

    override fun callback(frame: ImageProxy, params: Array<Any>): Any? {

        val result = WritableNativeMap()

        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        @SuppressLint("UnsafeOptInUsageError")
        val mediaImage: Image? = frame.image

        if (mediaImage != null) {
            val bitmap = convertImageProxyToBitmap(frame)          
            if (bitmap != null) {
         
                val brightness = calculateBrightnessScore(bitmap)
                val sharpness = calculateSharpnessScore(bitmap)              

                val inputImage = InputImage.fromBitmap(bitmap, 0)
                val task: Task<Text> = recognizer.process(inputImage)
                try {
                    val text: Text = Tasks.await(task)
                    result.putString("text", text.text)
                    result.putArray("blocks", getBlockArray(text.textBlocks))           
                    result.putDouble("brightness", brightness)
                    result.putDouble("sharpness", sharpness)

                } catch (e: Exception) {
                    return null
                }
            } else {
                return null
            }
        }

        val data = WritableNativeMap()
        data.putMap("result", result)
        return data
    }

    private fun convertImageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        val image = imageProxy.image ?: return null
        val yBuffer = image.planes[0].buffer // Y
        val uBuffer = image.planes[1].buffer // U
        val vBuffer = image.planes[2].buffer // V

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        val nv21 = ByteArray(ySize + uSize + vSize)
        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, imageProxy.width, imageProxy.height), 100, out)
        val byteArray = out.toByteArray()
        val originalBitmap = BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size)

        // Rotate the bitmap based on the rotation degrees
        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        val matrix = Matrix()
        matrix.postRotate(rotationDegrees.toFloat())

        return Bitmap.createBitmap(
            originalBitmap, 
            0, 
            0, 
            originalBitmap.width, 
            originalBitmap.height, 
            matrix, 
            true
        )
    }

    //Open CV Changes
    fun calculateBrightnessScore(bitmap: Bitmap): Double {
        val brightness = calculateBrightness(bitmap)
        return brightness
    }

    fun calculateBrightness(bitmap: Bitmap): Double {
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)
        val grayMat = Mat()
        Imgproc.cvtColor(mat, grayMat, Imgproc.COLOR_BGR2GRAY)

        val mean = MatOfDouble()
        val stddev = MatOfDouble()
        Core.meanStdDev(grayMat, mean, stddev)

        mat.release()
        grayMat.release()

        return mean.get(0, 0)[0]
    }

    //Higher scores mean sharper images,
    private fun calculateSharpnessScore(bitmap: Bitmap): Double {

        val mat = Mat()
        try {
            Utils.bitmapToMat(bitmap, mat)

            // Convert to grayscale
            Imgproc.cvtColor(mat, mat, Imgproc.COLOR_BGR2GRAY)

            // Apply Laplacian operator to detect edges
            val laplacianMat = Mat()
            Imgproc.Laplacian(mat, laplacianMat, CvType.CV_64F)

            // Compute the standard deviation of the Laplacian result
            val meanStdDev = MatOfDouble()
            val stdDevMat = MatOfDouble()

            org.opencv.core.Core.meanStdDev(laplacianMat, meanStdDev, stdDevMat)

            val stddev = stdDevMat.get(0, 0)?.get(0) ?: 0.0

            // Release resources
            mat.release()
            laplacianMat.release()
            meanStdDev.release()
            stdDevMat.release()

            return stddev
        } catch (e: Exception) {
            Log.e("openCV", "Error while calculating sharpness score", e)
            mat.release() // Ensure release even in error case
            throw e
        }
    }
}