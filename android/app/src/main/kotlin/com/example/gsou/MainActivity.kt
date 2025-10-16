package com.example.gsou

import android.app.Activity
import android.content.Intent
import android.content.ComponentName
import android.content.Context
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.content.ServiceConnection
import android.net.VpnService
import android.os.IBinder
import android.os.Bundle
import android.os.Build
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.Icon
import android.content.BroadcastReceiver
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.gsou.vpn.CoreVpnService

class MainActivity : FlutterActivity() {
	private var vpnBound = false
	private var vpnBinder: CoreVpnService.LocalBinder? = null
	private var pendingVpnPrepareResult: MethodChannel.Result? = null
	private var methodChannel: MethodChannel? = null
	private var dartReady: Boolean = false
	private var pendingShortcutAction: String? = null
	private var handlerReady: Boolean = false
	private var requestedBackground: Boolean = false
	private var tileActionReceiver: BroadcastReceiver? = null

	companion object {
		private const val REQ_VPN_PREPARE = 100
		const val ACTION_TILE_COMMAND = "com.example.gsou.TILE_COMMAND"
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
		methodChannel = MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"singbox/native"
		)
		methodChannel!!.setMethodCallHandler { call, result ->
			when (call.method) {
				// Dart 侧通知：已准备好接收回调
				"nativeReady" -> {
					dartReady = true
					// 只有当 Dart 已就绪且 Dart 侧声明已注册 handler 才发送
					if (handlerReady) {
						pendingShortcutAction?.let {
							try { 
								android.util.Log.i("QS", "Dart ready, processing pending action: $it")
								methodChannel?.invokeMethod(it, null) 
							} catch (_: Throwable) {}
							pendingShortcutAction = null
							// 注意：不在这里后台化！等 Dart 执行完成后会调用 shortcutActionCompleted
						}
						if (requestedBackground) {
							try {
								moveTaskToBack(true)
								overridePendingTransition(0, 0)
							} catch (_: Throwable) {}
							// 一次性后台化后清理标记与 action，避免影响后续从桌面正常进入
							requestedBackground = false
							try { this.intent?.action = null } catch (_: Throwable) {}
						}
					}
					result.success(true)
				}
				"shortcutHandlerReady" -> {
					handlerReady = true
					if (dartReady) {
						pendingShortcutAction?.let {
							try { 
								android.util.Log.i("QS", "Dart ready, processing pending action: $it")
								methodChannel?.invokeMethod(it, null) 
							} catch (_: Throwable) {}
							pendingShortcutAction = null
							// 注意：不在这里后台化！等 Dart 执行完成后会调用 shortcutActionCompleted
						}
						if (requestedBackground) {
							try {
								moveTaskToBack(true)
								overridePendingTransition(0, 0)
							} catch (_: Throwable) {}
							requestedBackground = false
							try { this.intent?.action = null } catch (_: Throwable) {}
						}
					}
					result.success(true)
				}
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
				"shortcutActionCompleted" -> {
					// Dart 层通知快捷方式操作已完成，现在可以安全后台化
					try { android.util.Log.i("QS", "Shortcut action completed, backgrounding MainActivity") } catch (_: Throwable) {}
					try {
						moveTaskToBack(true)
						overridePendingTransition(0, 0)
					} catch (_: Throwable) {}
					result.success(true)
				}
				else -> result.notImplemented()
			}
		}

		// 处理可能来自快捷方式的意图
		handleShortcutIntent(intent)
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		// 若由快捷方式进入，尽早设置透明主题，降低可见闪现
		try {
			val a = intent?.action
			android.util.Log.i("QS", "MainActivity onCreate: action=$a")
			if (a == "com.example.gsou.ACTION_VPN_ON" || a == "com.example.gsou.ACTION_VPN_OFF" || a == "com.example.gsou.ACTION_VPN_TOGGLE") {
				setTheme(R.style.ShortcutTheme)
			}
		} catch (_: Throwable) {}
		super.onCreate(savedInstanceState)

		// 注册广播接收器，接收 QS 磁贴命令
		registerTileCommandReceiver()
		
		// 尝试发布无图标的动态快捷方式，覆盖桌面可能缓存的静态样式
		publishTextOnlyShortcuts()
		
		//首次启动也处理 Intent
		try { android.util.Log.i("QS", "MainActivity onCreate: calling handleShortcutIntent") } catch (_: Throwable) {}
		handleShortcutIntent(intent)
	}
	
	override fun onDestroy() {
		super.onDestroy()
		// 注销广播接收器
		unregisterTileCommandReceiver()
	}
	
	private fun registerTileCommandReceiver() {
		try {
			if (tileActionReceiver == null) {
				tileActionReceiver = object : BroadcastReceiver() {
					override fun onReceive(context: Context?, intent: Intent?) {
						val action = intent?.getStringExtra("action") ?: return
						android.util.Log.i("QS", "MainActivity received tile command: $action dartReady=$dartReady handlerReady=$handlerReady")
						
						// 创建一个临时 Intent 来复用 handleShortcutIntent 逻辑
						val fakeIntent = Intent().apply { setAction(action) }
						handleShortcutIntent(fakeIntent)
					}
				}
				val filter = IntentFilter(ACTION_TILE_COMMAND)
				registerReceiver(tileActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
				android.util.Log.i("QS", "MainActivity: tile command receiver registered")
			}
		} catch (e: Throwable) {
			android.util.Log.e("QS", "Failed to register tile command receiver", e)
		}
	}
	
	private fun unregisterTileCommandReceiver() {
		try {
			tileActionReceiver?.let {
				unregisterReceiver(it)
				tileActionReceiver = null
				android.util.Log.i("QS", "MainActivity: tile command receiver unregistered")
			}
		} catch (e: Throwable) {
			android.util.Log.e("QS", "Failed to unregister tile command receiver", e)
		}
	}

	private fun publishTextOnlyShortcuts() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
		try {
			val sm = getSystemService(ShortcutManager::class.java) ?: return

			// 仅发布一个 TOGGLE 快捷方式
			val toggleIntent = Intent(this, ShortcutProxyActivity::class.java).apply {
				action = "com.example.gsou.ACTION_VPN_TOGGLE"
				setPackage(packageName)
				addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NO_ANIMATION)
			}
			val toggleBuilder = ShortcutInfo.Builder(this, "vpn_toggle")
				.setShortLabel(getString(R.string.shortcut_vpn_toggle_short))
				.setIntents(arrayOf(toggleIntent))

			// 提供透明图标，避免桌面灰圆占位
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
				val size = 108
				val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
				bmp.eraseColor(Color.TRANSPARENT)
				val transparentIcon = try { Icon.createWithAdaptiveBitmap(bmp) } catch (_: Throwable) { Icon.createWithBitmap(bmp) }
				toggleBuilder.setIcon(transparentIcon)
			}

			val toggle = toggleBuilder.build()
			sm.setDynamicShortcuts(listOf(toggle))
			sm.updateShortcuts(listOf(toggle))
		} catch (_: Throwable) {}
	}

	override fun onNewIntent(intent: android.content.Intent) {
		super.onNewIntent(intent)
		try { android.util.Log.i("QS", "MainActivity onNewIntent: action=${intent.action} dartReady=$dartReady handlerReady=$handlerReady") } catch (_: Throwable) {}
		setIntent(intent) // 重要：更新当前 Intent，否则 this.intent 仍是旧的
		handleShortcutIntent(intent)
	}
	
	override fun onStart() {
		super.onStart()
		// 当 Activity 从后台恢复到前台时，重新检查是否有待处理的 Intent
		try { android.util.Log.i("QS", "MainActivity onStart: checking intent=${intent?.action}") } catch (_: Throwable) {}
		handleShortcutIntent(intent)
	}

	override fun onResume() {
		super.onResume()
		// 仅在请求后台化的一次性场景触发，之后清理标记
		if (requestedBackground) {
			try {
				moveTaskToBack(true)
				overridePendingTransition(0, 0)
			} catch (_: Throwable) {}
			requestedBackground = false
			try { this.intent?.action = null } catch (_: Throwable) {}
		}
	}

	private fun handleShortcutIntent(intent: android.content.Intent?) {
		if (intent == null) return
		val action = intent.action ?: return
		// 注意：Android 12+ 禁止发送 ACTION_CLOSE_SYSTEM_DIALOGS，移除该广播
        try { android.util.Log.i("QS", "MainActivity handleShortcutIntent action=$action dartReady=$dartReady handlerReady=$handlerReady") } catch (_: Throwable) {}
		when (action) {
			"com.example.gsou.ACTION_VPN_ON" -> {
				// 切换到透明主题，尽量降低可见性
				try { setTheme(R.style.ShortcutTheme) } catch (_: Throwable) {}
				// 若未授权 VPN，先请求系统授权；授权完成后再派发“开启”动作
				val prep = VpnService.prepare(this)
				if (prep != null) {
					pendingShortcutAction = "shortcutVpnOn"
					requestedBackground = false // 保持前台以便用户授权
					startActivityForResult(prep, REQ_VPN_PREPARE)
					return
				}
				// 交给 Dart 层统一处理：启动连接；若 Dart 未就绪则缓存
				if (dartReady && handlerReady) {
					try { android.util.Log.i("QS", "MainActivity invoking shortcutVpnOn") } catch (_: Throwable) {}
					methodChannel?.invokeMethod("shortcutVpnOn", null)
					try {
						moveTaskToBack(true)
						// 切换到透明主题，尽量降低可见性
						try { setTheme(R.style.ShortcutTheme) } catch (_: Throwable) {}
						overridePendingTransition(0, 0)
					} catch (_: Throwable) {}
					// 清除 action 避免后续重复触发
					try { this.intent?.action = null } catch (_: Throwable) {}



				} else {
					pendingShortcutAction = "shortcutVpnOn"
					requestedBackground = true
				}
			}
			"com.example.gsou.ACTION_VPN_OFF" -> {
				// 切换到透明主题，尽量降低可见性
				try { setTheme(R.style.ShortcutTheme) } catch (_: Throwable) {}
				// 交给 Dart 层统一处理：断开连接
				if (dartReady && handlerReady) {
					try { android.util.Log.i("QS", "MainActivity invoking shortcutVpnOff (waiting for Dart callback) methodChannel=$methodChannel") } catch (_: Throwable) {}
					// 保持前台（透明）让 Dart 正常执行
					// Dart 执行完成后会调用 shortcutActionCompleted 通知后台化
					methodChannel?.invokeMethod("shortcutVpnOff", null)
				} else {
					// Dart 未就绪：缓存 action，但不后台化！让 Flutter 正常启动
					// Dart 初始化完成后会重新检查 Intent 并处理
					try { android.util.Log.i("QS", "MainActivity: Dart not ready, caching action and staying foreground") } catch (_: Throwable) {}
					pendingShortcutAction = "shortcutVpnOff"
					requestedBackground = false // 关键：不要立即后台化
				}
				// 无论哪种情况，都清空 Intent action 避免重复处理
				try { this.intent?.action = null } catch (_: Throwable) {}
			}
			"com.example.gsou.ACTION_VPN_TOGGLE" -> {
				try { setTheme(R.style.ShortcutTheme) } catch (_: Throwable) {}
				if (dartReady && handlerReady) {
					try { android.util.Log.i("QS", "MainActivity invoking shortcutVpnToggle (waiting for Dart callback)") } catch (_: Throwable) {}
					// 保持前台（透明）让 Dart 正常执行
					// Dart 执行完成后会调用 shortcutActionCompleted 通知后台化
					methodChannel?.invokeMethod("shortcutVpnToggle", null)
				} else {
					// Dart 未就绪：缓存 action，但不后台化！让 Flutter 正常启动
					try { android.util.Log.i("QS", "MainActivity: Dart not ready, caching action and staying foreground") } catch (_: Throwable) {}
					pendingShortcutAction = "shortcutVpnToggle"
					requestedBackground = false // 关键：不要立即后台化
				}
				// 无论哪种情况，都清空 Intent action 避免重复处理
				try { this.intent?.action = null } catch (_: Throwable) {}
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
			} else {
				// 来自快捷方式的授权流程：授权成功后触发连接并后台化
				if (resultCode == Activity.RESULT_OK && pendingShortcutAction == "shortcutVpnOn") {
					try { methodChannel?.invokeMethod("shortcutVpnOn", null) } catch (_: Throwable) {}
					try {
						moveTaskToBack(true)
						overridePendingTransition(0, 0)
					} catch (_: Throwable) {}
					// 清理，避免影响后续从桌面正常进入
					requestedBackground = false
					try { this.intent?.action = null } catch (_: Throwable) {}
					pendingShortcutAction = null
				}
			}
		}
	}
}
