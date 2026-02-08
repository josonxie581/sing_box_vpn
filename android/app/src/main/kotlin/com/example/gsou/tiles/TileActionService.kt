package com.example.gsou.tiles

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.net.VpnService
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.example.gsou.MainActivity
import com.example.gsou.R
import com.example.gsou.ShortcutProxyActivity
import com.example.gsou.vpn.CoreVpnService

class TileActionService : Service() {
    companion object {
        const val EXTRA_ACTION = "extra_action"
        const val ACTION_ON = "com.example.gsou.ACTION_VPN_ON"
        const val ACTION_OFF = "com.example.gsou.ACTION_VPN_OFF"
        const val ACTION_TOGGLE = "com.example.gsou.ACTION_VPN_TOGGLE"
        private const val NOTIF_CHANNEL_ID = "vpn_tile_action"
        private const val NOTIF_ID = 1001
    }

    private var vpnBound = false
    private var vpnBinder: CoreVpnService.LocalBinder? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            vpnBound = true
            vpnBinder = service as? CoreVpnService.LocalBinder
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            vpnBound = false
            vpnBinder = null
        }
    }

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        android.util.Log.i("TileActionService", "onCreate: service created")
        startAsForeground("处理中…")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val act = intent?.getStringExtra(EXTRA_ACTION)
        android.util.Log.i("TileActionService", "onStartCommand: action=$act")
        if (act != null) {
            handleAction(act)
        }
        // 短生命周期服务：处理完立即退出
        Handler(Looper.getMainLooper()).postDelayed({ safeStop() }, 2000)
        return START_NOT_STICKY
    }

    private fun handleAction(action: String) {
        android.util.Log.i("TileActionService", "handleAction: raw action=$action")
        
        // 检测当前 VPN 状态
        val cm = getSystemService(ConnectivityManager::class.java)
        val vpnActive = cm?.allNetworks?.any { n ->
            val caps = cm.getNetworkCapabilities(n)
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        } == true
        
        android.util.Log.i("TileActionService", "handleAction: current VPN active=$vpnActive")
        
        // 决定目标动作
        val targetAction = when (action) {
            ACTION_ON -> ACTION_ON
            ACTION_OFF -> ACTION_OFF
            ACTION_TOGGLE -> if (vpnActive) ACTION_OFF else ACTION_ON
            else -> ACTION_TOGGLE
        }
        
        android.util.Log.i("TileActionService", "handleAction: target action=$targetAction")
        
        // 如果要开启，检查 VPN 权限
        if (targetAction == ACTION_ON) {
            val prep = VpnService.prepare(this)
            if (prep != null) {
                android.util.Log.i("TileActionService", "handleAction: VPN not prepared, posting notification")
                postNeedPermissionNotification(ACTION_ON)
                return
            }
        }
        
        // 方案改为发送广播给 MainActivity，避免 Activity 生命周期问题
        try {
            android.util.Log.i("TileActionService", "handleAction: sending broadcast to MainActivity")
            
            // 发送广播给 MainActivity（如果正在运行）
            val broadcastIntent = Intent("com.example.gsou.TILE_COMMAND").apply {
                putExtra("action", targetAction)
                setPackage(packageName)
            }
            sendBroadcast(broadcastIntent)
            android.util.Log.i("TileActionService", "handleAction: broadcast sent successfully")
            
            // 如果 MainActivity 没有运行，启动它
            val mainIntent = Intent(this, MainActivity::class.java).apply {
                setAction(targetAction)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(mainIntent)
            android.util.Log.i("TileActionService", "handleAction: MainActivity launch attempted")
            
            // 延迟刷新磁贴状态
            Handler(Looper.getMainLooper()).postDelayed({
                try { 
                    sendBroadcast(Intent("com.example.gsou.ACTION_REFRESH_QS_TILES"))
                    android.util.Log.i("TileActionService", "handleAction: refresh broadcast sent")
                } catch (_: Throwable) {}
            }, 1500)
        } catch (e: Throwable) {
            android.util.Log.e("TileActionService", "handleAction: failed to start activity", e)
        }
    }

    private fun startAsForeground(contentText: String) {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(NOTIF_CHANNEL_ID, "VPN 操作", NotificationManager.IMPORTANCE_MIN)
            nm?.createNotificationChannel(ch)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIF_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val notif = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("VPN 操作")
            .setContentText(contentText)
            .setOngoing(true)
            .build()
        startForeground(NOTIF_ID, notif)
    }

    private fun postNeedPermissionNotification(action: String) {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(NOTIF_CHANNEL_ID, "VPN 操作", NotificationManager.IMPORTANCE_DEFAULT)
            nm?.createNotificationChannel(ch)
        }
        val launch = Intent(this, MainActivity::class.java).apply {
            this.setAction(action)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE 
        else 
            PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getActivity(this, 0, launch, piFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIF_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val notif = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("需要授权以开启 VPN")
            .setContentText("点击此处打开应用完成授权")
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        nm?.notify(NOTIF_ID + 1, notif)
    }

    private fun cleanup() {
        try {
            if (vpnBound) {
                unbindService(connection)
                vpnBound = false
                vpnBinder = null
            }
        } catch (_: Throwable) {}
    }

    private fun safeStop() {
        android.util.Log.i("TileActionService", "safeStop: stopping service")
        cleanup()
        try { stopForeground(true) } catch (_: Throwable) {}
        try { stopSelf() } catch (_: Throwable) {}
    }

    override fun onDestroy() {
        android.util.Log.i("TileActionService", "onDestroy: service destroyed")
        cleanup()
        super.onDestroy()
    }
}
