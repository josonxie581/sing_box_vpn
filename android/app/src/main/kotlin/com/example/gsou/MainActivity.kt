package com.example.gsou

import android.app.Activity
import android.content.Intent
import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.net.VpnService
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.gsou.vpn.CoreVpnService

class MainActivity : FlutterActivity() {
	private var vpnBound = false
	private var vpnBinder: CoreVpnService.LocalBinder? = null
	private var pendingVpnPrepareResult: MethodChannel.Result? = null

	companion object {
		private const val REQ_VPN_PREPARE = 100
	}

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

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"singbox/native"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"vpnIsBound" -> {
					result.success(vpnBound)
				}
				"vpnPrepare" -> {
					val intent = VpnService.prepare(this)
					if (intent != null) {
						// 弹出系统授权对话框，并在 onActivityResult 中异步返回结果
						pendingVpnPrepareResult = result
						startActivityForResult(intent, REQ_VPN_PREPARE)
					} else {
						// 已经授权过，直接返回 true
						result.success(true)
					}
				}
				"vpnBind" -> {
					val intent = Intent(this, CoreVpnService::class.java)
					val ok = bindService(intent, connection, Context.BIND_AUTO_CREATE)
					result.success(ok)
				}
				"vpnUnbind" -> {
					if (vpnBound) {
						unbindService(connection)
						vpnBound = false
						vpnBinder = null
					}
					result.success(true)
				}
				"vpnOpenTunAndGetFd" -> {
					val mtu = (call.argument<Int>("mtu") ?: 1500)
					val addr = call.argument<String>("ipv4Cidr") ?: "10.225.0.2/30"
					val route = call.argument<String>("routeCidr") ?: "0.0.0.0/0"
					val session = call.argument<String>("session") ?: "Sing-Box VPN"
					if (!vpnBound || vpnBinder == null) {
						android.util.Log.w("CoreVpnService", "vpnOpenTunAndGetFd called before service bound")
						result.success(-2)
						return@setMethodCallHandler
					}
					val fd = vpnBinder?.openTunAndGetFd(mtu, addr, route, session) ?: -1
					result.success(fd)
				}
				"vpnCloseTun" -> {
					vpnBinder?.closeTun()
					result.success(true)
				}
				else -> result.notImplemented()
			}
		}
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode == REQ_VPN_PREPARE) {
			val pending = pendingVpnPrepareResult
			pendingVpnPrepareResult = null
			if (pending != null) {
				pending.success(resultCode == Activity.RESULT_OK)
			}
		}
	}
}
