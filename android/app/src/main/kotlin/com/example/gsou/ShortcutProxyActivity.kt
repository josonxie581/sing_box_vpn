package com.example.gsou

import android.app.Activity
import android.content.Intent
import android.os.Bundle

// 透明代理 Activity：作为快捷方式落点，立即转发到 MainActivity 并结束自身
class ShortcutProxyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 应用无界面主题，避免任何可见 UI
        try { setTheme(R.style.ShortcutProxyTheme) } catch (_: Throwable) {}
        super.onCreate(savedInstanceState)

    // 注意：从 QS Tile 启动时，过早关闭系统对话框可能影响 Activity 拉起，改为在转发后再关闭

    val action = intent?.action
    try { android.util.Log.i("QS", "Proxy launched with action=$action") } catch (_: Throwable) {}
        val forward = Intent(this, MainActivity::class.java)
        if (action != null) forward.action = action
        // 使用 CLEAR_TOP 确保能唤醒后台的 MainActivity
        forward.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_ACTIVITY_NO_ANIMATION
        )
    try { android.util.Log.i("QS", "Proxy forwarding to MainActivity with action=${forward.action} flags=${forward.flags}") } catch (_: Throwable) {}
    try { 
        startActivity(forward) 
        android.util.Log.i("QS", "Proxy startActivity SUCCESS")
    } catch (e: Throwable) { 
        try { android.util.Log.e("QS", "Proxy startActivity failed: ${e.message}", e) } catch (_: Throwable) {} 
    }

        // 清理自身 intent 的 action，避免系统复用旧值影响下一次触发
    try { intent?.action = null; android.util.Log.i("QS", "Proxy cleared self intent action") } catch (_: Throwable) {}

        // 注意：Android 12+ 禁止发送 ACTION_CLOSE_SYSTEM_DIALOGS，移除该广播

        // 立即结束自身，彻底避免闪现
        finish()
        overridePendingTransition(0, 0)
    }
}
