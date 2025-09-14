package main

/*
#include <stdlib.h>

// 日志回调声明与调用助手
typedef void (*LogCallback)(const char* msg);
static inline void callLog(LogCallback cb, const char* msg) {
	if (cb) { cb(msg); }
}
*/
import "C"
import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"
	"unsafe"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

var (
	instance *box.Box
	mu       sync.Mutex
	ctx      context.Context
	cancel   context.CancelFunc
	// C 侧回调指针
	logCB C.LogCallback
)

var lastError string

// 诊断文件路径（若 Dart 侧未注册回调仍可落盘）
func diagFilePath() string {
	// 尝试用户文档目录
	home, _ := os.UserHomeDir()
	if home != "" {
		p := home + string(os.PathSeparator) + "Documents" + string(os.PathSeparator) + "sing-box"
		_ = os.MkdirAll(p, 0755)
		return p + string(os.PathSeparator) + "early_start.log"
	}
	// 退回当前目录
	return "early_start.log"
}

func dbg(msg string) {
	if logCB != nil {
		// 若已有回调，交由上层统一写
		c := C.CString("[NATIVE] " + msg)
		C.callLog(logCB, c)
		C.free(unsafe.Pointer(c))
	} else {
		// 没有回调，直接写文件（追加）
		f, err := os.OpenFile(diagFilePath(), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			return
		}
		_, _ = f.WriteString(fmt.Sprintf("%s [NATIVE] %s\n", timestamp(), msg))
		_ = f.Close()
	}
}

func timestamp() string { return time.Now().Format("2006-01-02T15:04:05.000Z07:00") }

func setLastError(err error) {
	if err != nil {
		lastError = err.Error()
	} else {
		lastError = ""
	}
}

// FFI 平台日志输出，实现 sing-box/log.PlatformWriter。若 Dart 侧未设置回调，则此 writer 不输出。
type ffiPlatformWriter struct{}

func (w *ffiPlatformWriter) DisableColors() bool { return true }
func (w *ffiPlatformWriter) WriteMessage(level log.Level, message string) {
	if logCB != nil {
		cmsg := C.CString(message)
		C.callLog(logCB, cmsg)
		C.free(unsafe.Pointer(cmsg))
	}
}

//export InitSingBox
func InitSingBox() int {
	mu.Lock()
	defer mu.Unlock()
	dbg("InitSingBox enter")

	ctx, cancel = context.WithCancel(context.Background())
	if logCB != nil {
		msg := C.CString("sing-box 初始化完成")
		C.callLog(logCB, msg)
		C.free(unsafe.Pointer(msg))
	}
	dbg("InitSingBox leave")

	return 0
}

//export StartSingBox
func StartSingBox(configJSON *C.char) int {
	dbg("StartSingBox enter prelock")
	mu.Lock()
	dbg("StartSingBox got lock")
	defer mu.Unlock()
	dbg("StartSingBox enter")

	if instance != nil {
		if logCB != nil {
			msg := C.CString("sing-box 已经在运行")
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		dbg("StartSingBox fast-return already running")
		return -1 // 已经在运行
	}

	// Watchdog: 每 1s 输出一次阶段进度，帮助定位卡住点
	startTS := time.Now()
	stage := "init"
	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return
			case t := <-ticker.C:
				elapsed := t.Sub(startTS).Milliseconds()
				dbg(fmt.Sprintf("StartSingBox watchdog elapsed=%dms stage=%s", elapsed, stage))
			}
		}
	}()
	defer close(done)

	// 解析配置（必须使用带上下文的解析以启用各注册表与 typed DNS 等选项）
	var options option.Options
	configStr := C.GoString(configJSON)
	ctxWithRegistry := include.Context(ctx)
	stage = "parse_options"
	dbg("StartSingBox phase=parse_options begin")
	if err := sjson.UnmarshalContext(ctxWithRegistry, []byte(configStr), &options); err != nil {
		setLastError(fmt.Errorf("parse options: %w", err))
		if logCB != nil {
			msg := C.CString(fmt.Sprintf("配置解析失败: %v", err))
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		dbg("StartSingBox phase=parse_options fail")
		return -2
	}
	dbg("StartSingBox phase=parse_options ok")

	// 创建 sing-box 实例（使用内置日志系统；如设置了回调，则通过 PlatformWriter 输出）
	var err error
	var pw log.PlatformWriter
	if logCB != nil {
		pw = &ffiPlatformWriter{}
	}
	// 确保在 Context 中注入默认的 Inbound/Outbound/Endpoint/DNS/Service 注册表
	// 注意：ctxWithRegistry 已在上方用于解析
	stage = "box.New"
	dbg("StartSingBox phase=box.New begin")
	instance, err = box.New(box.Options{
		Context:           ctxWithRegistry,
		Options:           options,
		PlatformLogWriter: pw,
	})

	if err != nil {
		setLastError(fmt.Errorf("box.New: %w", err))
		if logCB != nil {
			msg := C.CString(fmt.Sprintf("创建实例失败: %v", err))
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		dbg("StartSingBox phase=box.New fail")
		return -3
	}
	dbg("StartSingBox phase=box.New ok")

	// 启动服务
	stage = "instance.Start"
	dbg("StartSingBox phase=instance.Start begin")
	err = instance.Start()
	if err != nil {
		setLastError(fmt.Errorf("instance.Start: %w", err))
		if logCB != nil {
			msg := C.CString(fmt.Sprintf("启动失败: %v", err))
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		instance.Close()
		instance = nil
		dbg("StartSingBox phase=instance.Start fail")
		return -4
	}
	dbg("StartSingBox phase=instance.Start ok")
	stage = "done"

	if logCB != nil {
		msg := C.CString("sing-box 启动成功")
		C.callLog(logCB, msg)
		C.free(unsafe.Pointer(msg))
	}
	dbg("StartSingBox leave success")

	return 0
}

//export StopSingBox
func StopSingBox() int {
	mu.Lock()
	defer mu.Unlock()

	if instance == nil {
		if logCB != nil {
			msg := C.CString("sing-box 未运行")
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		return -1 // 未运行
	}

	err := instance.Close()
	if err != nil {
		if logCB != nil {
			msg := C.CString(fmt.Sprintf("停止失败: %v", err))
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		return -2
	}

	instance = nil

	if logCB != nil {
		msg := C.CString("sing-box 已停止")
		C.callLog(logCB, msg)
		C.free(unsafe.Pointer(msg))
	}

	return 0
}

//export IsRunning
func IsRunning() int {
	mu.Lock()
	defer mu.Unlock()

	if instance != nil {
		return 1
	}
	return 0
}

//export TestConfig
func TestConfig(configJSON *C.char) int {
	var options option.Options
	configStr := C.GoString(configJSON)
	ctxLocal := ctx
	if ctxLocal == nil {
		ctxLocal = context.Background()
	}
	ctxWithRegistry := include.Context(ctxLocal)

	if err := sjson.UnmarshalContext(ctxWithRegistry, []byte(configStr), &options); err != nil {
		setLastError(fmt.Errorf("parse options: %w", err))
		if logCB != nil {
			msg := C.CString(fmt.Sprintf("配置无效: %v", err))
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		return -1
	}

	// TODO: 可以添加更详细的配置验证

	if logCB != nil {
		msg := C.CString("=配置验证通过")
		C.callLog(logCB, msg)
		C.free(unsafe.Pointer(msg))
	}
	return 0
}

//export GetVersion
func GetVersion() *C.char {
	// 返回版本信息
	version := "sing-box integrated v1.0.0"
	return C.CString(version)
}

//export Cleanup
func Cleanup() {
	mu.Lock()
	defer mu.Unlock()

	if instance != nil {
		instance.Close()
		instance = nil
	}

	if cancel != nil {
		cancel()
	}

	if logCB != nil {
		msg := C.CString("资源清理完成")
		C.callLog(logCB, msg)
		C.free(unsafe.Pointer(msg))
	}
}

//export SbGetLastError
func SbGetLastError() *C.char {
	if lastError == "" {
		return C.CString("")
	}
	return C.CString(lastError)
}

//export FreeCString
func FreeCString(p *C.char) {
	if p != nil {
		C.free(unsafe.Pointer(p))
	}
}

//export RegisterLogCallback
func RegisterLogCallback(cb C.LogCallback) {
	mu.Lock()
	defer mu.Unlock()
	logCB = cb
}

func main() {
	// 这个函数需要存在，但不会被调用
}
