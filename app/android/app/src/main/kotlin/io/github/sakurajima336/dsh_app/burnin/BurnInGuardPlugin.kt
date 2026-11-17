package io.github.sakurajima336.dsh_app.burnin

import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.random.Random

/**
 * 防烧屏屏保的系统悬浮窗（MethodChannel `dsh/burn_in_guard`，Dart 侧在
 * `lib/ui/burn_in/`）。应用内图层盖不住别的应用的悬浮窗，所以触发时改用
 * TYPE_APPLICATION_OVERLAY 的全屏黑窗盖住一切应用层窗口，只留一行
 * 「工作中」移动；手指一碰窗口自己先消失，再回告 Dart 重置计时。
 * 系统自己的通知栏/控制中心任何应用都盖不住，那不在这里的承诺内。
 */
class BurnInGuardPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var app: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        app = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        BurnInGuard.attach(app, channel)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        BurnInGuard.detach()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> result.success(
                BurnInGuard.show(
                    call.argument<String>("mode") ?: "spots",
                    call.argument<String>("text") ?: "Working",
                ),
            )
            "hide" -> {
                BurnInGuard.hide()
                result.success(null)
            }
            "canDraw" -> result.success(BurnInGuard.canDraw())
            "openPermissionSettings" -> {
                openPermissionSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openPermissionSettings() {
        val page = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${app.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            app.startActivity(page)
        } catch (_: Exception) {
            try {
                app.startActivity(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        const val CHANNEL = "dsh/burn_in_guard"
    }
}

object BurnInGuard {
    private var app: Context? = null
    private var channel: MethodChannel? = null
    private var view: BurnInGuardView? = null

    fun attach(context: Context, ch: MethodChannel) {
        app = context
        channel = ch
    }

    fun detach() {
        hide()
        app = null
        channel = null
    }

    fun canDraw(): Boolean =
        try {
            Settings.canDrawOverlays(app)
        } catch (_: Exception) {
            false
        }

    /** True when the window really went up; vendor ROMs can refuse even with permission. */
    fun show(mode: String, text: String): Boolean {
        val context = app ?: return false
        hide()
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val guard = BurnInGuardView(context, mode, text) { onTouched() }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.OPAQUE,
        )
        params.gravity = Gravity.TOP or Gravity.START
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            params.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        return try {
            wm.addView(guard, params)
            view = guard
            guard.start()
            true
        } catch (_: Exception) {
            false
        }
    }

    fun hide() {
        val current = view ?: return
        view = null
        current.stop()
        try {
            (app?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.removeView(current)
        } catch (_: Exception) {
        }
    }

    private fun onTouched() {
        hide()
        try {
            channel?.invokeMethod("dismissedByTouch", null)
        } catch (_: Exception) {
        }
    }
}

/** 全屏纯黑，只画一行会动的文字：随机位置（上/中/下轮换）或满屏弹跳（撞边换色）。 */
class BurnInGuardView(
    context: Context,
    private val mode: String,
    private val text: String,
    private val onTouch: () -> Unit,
) : View(context) {
    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = PALETTE[0]
        textSize = 20f * resources.displayMetrics.scaledDensity
        typeface = Typeface.DEFAULT
    }
    private val textWidth = paint.measureText(text)
    private val textHeight = paint.fontMetrics.let { it.descent - it.ascent }
    private val handler = Handler(Looper.getMainLooper())

    // spots 模式：三个纵向位置轮换，同一个不连着出现两次；横向再带随机偏移。
    private var slot = Random.nextInt(SLOT_Y.size)
    private var spotX = 0.3f
    private val spotTick = object : Runnable {
        override fun run() {
            var next = Random.nextInt(SLOT_Y.size)
            while (next == slot) next = Random.nextInt(SLOT_Y.size)
            slot = next
            spotX = 0.08f + Random.nextFloat() * 0.5f
            invalidate()
            handler.postDelayed(this, DWELL_MS)
        }
    }

    // bounce 模式：匀速斜飞，撞边反弹并换一种暗色。
    private var posX = 40f * density
    private var posY = 40f * density
    private var velX = (if (Random.nextBoolean()) 1 else -1) * 110f * density
    private var velY = (if (Random.nextBoolean()) 1 else -1) * 84f * density
    private var colorIndex = 0
    private var lastFrameNs = 0L
    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (lastFrameNs != 0L) {
                val dt = (frameTimeNanos - lastFrameNs) / 1e9f
                if (dt > 0f) stepBounce(dt)
            }
            lastFrameNs = frameTimeNanos
            invalidate()
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    fun start() {
        if (mode == "bounce") {
            lastFrameNs = 0L
            Choreographer.getInstance().postFrameCallback(frameCallback)
        } else {
            handler.postDelayed(spotTick, DWELL_MS)
        }
    }

    fun stop() {
        handler.removeCallbacks(spotTick)
        Choreographer.getInstance().removeFrameCallback(frameCallback)
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    private fun stepBounce(dt: Float) {
        val maxX = (width - textWidth).coerceAtLeast(0f)
        val maxY = (height - textHeight).coerceAtLeast(0f)
        posX += velX * dt
        posY += velY * dt
        var bounced = false
        if (posX <= 0f) {
            posX = 0f
            velX = abs(velX)
            bounced = true
        }
        if (posX >= maxX) {
            posX = maxX
            velX = -abs(velX)
            bounced = true
        }
        if (posY <= 0f) {
            posY = 0f
            velY = abs(velY)
            bounced = true
        }
        if (posY >= maxY) {
            posY = maxY
            velY = -abs(velY)
            bounced = true
        }
        if (bounced) {
            colorIndex = (colorIndex + 1) % PALETTE.size
            paint.color = PALETTE[colorIndex]
        }
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(Color.BLACK)
        val baseline: Float
        val x: Float
        if (mode == "bounce") {
            x = posX
            baseline = posY - paint.fontMetrics.ascent
        } else {
            x = spotX * (width - textWidth).coerceAtLeast(0f)
            val centerY = SLOT_Y[slot] * height
            baseline = centerY - (paint.fontMetrics.ascent + paint.fontMetrics.descent) / 2f
        }
        canvas.drawText(text, x, baseline, paint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_DOWN) onTouch()
        return true
    }

    companion object {
        private const val DWELL_MS = 4000L
        private val SLOT_Y = floatArrayOf(0.18f, 0.5f, 0.82f)
        private val PALETTE = intArrayOf(
            0xB3FFFFFF.toInt(),
            0xB3FFD54F.toInt(),
            0xB3A5D6A7.toInt(),
            0xB390CAF9.toInt(),
            0xB3CE93D8.toInt(),
            0xB3FFAB91.toInt(),
        )
    }
}
