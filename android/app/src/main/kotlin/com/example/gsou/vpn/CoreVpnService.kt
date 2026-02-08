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
    // 记录已分离给 native 的原始 FD，由 native 持有与关闭
    private var rawTunFd: Int = -1

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
                // 将当前应用排除在 VPN 之外，避免本进程的外连（连接代理服务器等）被再次重定向回 TUN 造成环路
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: Throwable) {
                    android.util.Log.w("CoreVpnService", "addDisallowedApplication failed: ${e.message}")
                }
                // 地址与路由：最小可用配置，后续由 sing-box 进行实际转发
                val parts = ipv4Cidr.split("/")
                val addr = parts[0]
                val prefix = parts.getOrNull(1)?.toIntOrNull() ?: 30
                builder.addAddress(addr, prefix)
                val rParts = routeCidr.split("/")
                val r = rParts[0]
                val rPrefix = rParts.getOrNull(1)?.toIntOrNull() ?: 0
                builder.addRoute(r, rPrefix)

                // 额外捕获 IPv6，全局导入 ::/0，分配一个私有IPv6地址
                try {
                    builder.addAddress("fd00:1:fd00::2", 120)
                    builder.addRoute("::", 0)
                } catch (_: Throwable) {
                    // 某些设备/ROM 可能不支持，忽略
                }

                // 设置系统 DNS，便于 Android 识别该 VPN 网络可用
                try {
                    builder.addDnsServer("8.8.8.8")
                    builder.addDnsServer("223.5.5.5")
                    builder.addDnsServer("2001:4860:4860::8888")
                } catch (_: Throwable) {}
                val pfd = builder.establish()
                if (pfd == null) {
                    android.util.Log.e("CoreVpnService", "establish() returned null")
                    return -1
                }
                // 如之前有旧的 wrapper，先尝试关闭（若之前已 detach，不会影响底层 FD）
                try { tunInterface?.close() } catch (_: Throwable) {}
                tunInterface = null
                // 将底层 FD 的所有权移交给 native（detach 后，关闭 PFD 不会再关闭底层 FD）
                val fd = try { pfd.detachFd() } catch (e: Throwable) {
                    android.util.Log.e("CoreVpnService", "detachFd failed: ${e.message}", e)
                    try { pfd.close() } catch (_: Throwable) {}
                    return -1
                }
                // 关闭 wrapper 自身（不会影响已分离的底层 FD）
                try { pfd.close() } catch (_: Throwable) {}
                rawTunFd = fd
                android.util.Log.i("CoreVpnService", "TUN established fd=${fd}")
                return fd
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
        // 注意：底层 FD 的关闭由 native/sing-box 负责（我们在 openTunAndGetFd 中已 detach 并交出所有权）。
        // 这里不再关闭任何 ParcelFileDescriptor 或原始 FD，以避免 fdsan double-close。
        tunInterface = null
        rawTunFd = -1
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
