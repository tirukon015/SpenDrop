package com.spendrop.app.ui.camera

import android.net.Uri
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.spendrop.app.permissions.PermissionManager
import com.spendrop.app.permissions.PermissionStatus
import com.spendrop.app.permissions.SpenDropAccess
import java.io.File
import java.util.UUID

/**
 * In-app camera for photographing a paper receipt. Reached only through the camera permission gate; if access is
 * revoked meanwhile (e.g. from Settings) it closes instead of failing. The photo goes into SpenDrop's private cache
 * and then through the normal import (OCR → review → save). Nothing is written to the gallery.
 */
@Composable
fun ReceiptCameraScreen(onCaptured: (Uri) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    var capture by remember { mutableStateOf<ImageCapture?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val allowed = remember { PermissionManager(context).status(SpenDropAccess.CAMERA) == PermissionStatus.GRANTED }
    if (!allowed) { androidx.compose.runtime.LaunchedEffect(Unit) { onClose() }; return }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx -> PreviewView(ctx).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } },
        )
        { view ->
            if (capture == null) {
                val providerFuture = ProcessCameraProvider.getInstance(context)
                providerFuture.addListener({
                    runCatching {
                        val provider = providerFuture.get()
                        val preview = Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
                        val ic = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY).build()
                        provider.unbindAll()
                        provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, ic)
                        capture = ic
                    }.onFailure { error = "The camera couldn't start. Close other camera apps and try again." }
                }, ContextCompat.getMainExecutor(context))
            }
        }
        DisposableEffect(Unit) {
            onDispose { runCatching { ProcessCameraProvider.getInstance(context).get().unbindAll() } }
        }
        // Receipt frame guide
        Box(Modifier.align(Alignment.Center).fillMaxWidth(0.82f).fillMaxSize(0.7f).border(2.dp, Color.White.copy(alpha = 0.7f), RoundedCornerShape(16.dp)))
        IconButton(onClick = onClose, modifier = Modifier.statusBarsPadding().padding(8.dp)) { Icon(Icons.Filled.Close, "Close camera", tint = Color.White) }
        Column(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(error ?: "Fit the receipt inside the frame", color = Color.White, modifier = Modifier.padding(bottom = 16.dp))
            Box(
                Modifier.size(76.dp).border(4.dp, Color.White, CircleShape).padding(8.dp).background(if (capture != null && !busy) Color.White else Color.Gray, CircleShape)
                    .semantics { contentDescription = "Take photo"; role = Role.Button }
                    .let { m ->
                        m.clickable(enabled = capture != null && !busy) {
                            val ic = capture ?: return@clickable
                            busy = true
                            val dir = File(context.cacheDir, "imports").apply { mkdirs() }
                            val file = File(dir, "camera-${UUID.randomUUID()}.jpg")
                            ic.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(context),
                                object : ImageCapture.OnImageSavedCallback {
                                    override fun onImageSaved(output: ImageCapture.OutputFileResults) { busy = false; onCaptured(Uri.fromFile(file)) }
                                    override fun onError(exception: ImageCaptureException) { busy = false; file.delete(); error = "The photo couldn't be taken. Try again." }
                                })
                        }
                    },
                contentAlignment = Alignment.Center,
            ) { if (busy) CircularProgressIndicator(Modifier.size(28.dp), color = Color.Black) }
        }
    }
}
