package com.example.gsou.tiles

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.example.gsou.ShortcutProxyActivity
import android.os.Handler
import android.os.Looper
import android.net.ConnectivityManager

class VpnToggleTileService : TileService() {
    private val refreshReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == "com.example.gsou.ACTION_REFRESH_QS_TILES") {
                try { updateTileState() } catch (_: Throwable) {}
            }
        }
    }
    override fun onTileAdded() {
        super.onTileAdded()
        updateTileState()
    }
    override fun onStartListening() {
        super.onStartListening()
        try { registerReceiver(refreshReceiver, android.content.IntentFilter("com.example.gsou.ACTION_REFRESH_QS_TILES")) } catch (_: Throwable) {}
        // 注意：Android 12+ 禁止发送 ACTION_CLOSE_SYSTEM_DIALOGS，移除该广播
        updateTileState()
    }
    override fun onStopListening() {
        super.onStopListening()
        try { unregisterReceiver(refreshReceiver) } catch (_: Throwable) {}
    }

    override fun onClick() {
        super.onClick()
        val intent = Intent(this, TileActionService::class.java).apply {
            putExtra(TileActionService.EXTRA_ACTION, "com.example.gsou.ACTION_VPN_TOGGLE")
        }
        try { android.util.Log.i("QS", "Toggle tile clicked: starting TileActionService") } catch (_: Throwable) {}
        try { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent) } catch (e: Throwable) {
            try { android.util.Log.e("QS", "Toggle tile: startService failed: ${e.message}", e) } catch (_: Throwable) {}
        }
        // 轻微延迟后刷新状态（不置 UNAVAILABLE，避免出现灰不可点）
        try { Handler(Looper.getMainLooper()).postDelayed({ updateTileState() }, 800) } catch (_: Throwable) {}
    }

    private fun updateTileState() {
        try {
            val cm = getSystemService(ConnectivityManager::class.java)
            val active = cm?.allNetworks?.any { n ->
                val caps = cm.getNetworkCapabilities(n)
                caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) == true
            } == true
            // Toggle 磁贴：VPN 已连接则点亮，未连接则灰
            qsTile?.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            qsTile?.updateTile()
        } catch (_: Throwable) {}
    }
}
