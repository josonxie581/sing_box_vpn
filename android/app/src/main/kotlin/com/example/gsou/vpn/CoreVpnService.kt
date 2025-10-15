package com.example.gsou.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor

class CoreVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onDestroy() {
        super.onDestroy()
        closeTun()
    }

    override fun onBind(intent: android.content.Intent?): IBinder? {
        // 允许绑定访问，供 Activity 通过 Binder 调用 openTun/closeTun
        return LocalBinder()
    }

    inner class LocalBinder : Binder() {
        fun openTunAndGetFd(
            mtu: Int = 1500,
            ipv4Cidr: String = "10.225.0.2/30",
            routeCidr: String = "0.0.0.0/0",
            sessionName: String = "Sing-Box VPN"
        ): Int {
            try {
                ensureChannel()
                startForegroundService(sessionName)
                val builder = Builder()
                builder.setSession(sessionName)
                builder.setMtu(mtu)
                // 地址与路由：最小可用配置，后续由 sing-box 进行实际转发
                val parts = ipv4Cidr.split("/")
                val addr = parts[0]
                val prefix = parts.getOrNull(1)?.toIntOrNull() ?: 30
                builder.addAddress(addr, prefix)
                val rParts = routeCidr.split("/")
                val r = rParts[0]
                val rPrefix = rParts.getOrNull(1)?.toIntOrNull() ?: 0
                builder.addRoute(r, rPrefix)
                val pfd = builder.establish()
                tunInterface?.close()
                tunInterface = pfd
                android.util.Log.i("CoreVpnService", "TUN established fd=${pfd?.fd ?: -1}")
                return pfd?.fd ?: -1
            } catch (e: Throwable) {
                android.util.Log.e("CoreVpnService", "openTunAndGetFd failed: ${e.message}", e)
                return -1
            }
        }

        fun closeTun() {
            this@CoreVpnService.closeTun()
        }
    }

    private fun closeTun() {
        tunInterface?.close()
        tunInterface = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun startForegroundService(sessionName: String) {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle(sessionName)
            .setContentText("正在运行")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .build()
        // Android 14+ 要求指定前台服务类型，已在 Manifest 上声明 specialUse
        startForeground(NOTIFY_ID, notification)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(CHANNEL_ID, "VPN", NotificationManager.IMPORTANCE_LOW)
            mgr.createNotificationChannel(ch)
        }
    }

    companion object {
        private const val CHANNEL_ID = "vpn_channel"
        private const val NOTIFY_ID = 1
    }
}
