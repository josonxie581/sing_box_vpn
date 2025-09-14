package main

// #include <stdlib.h>
import "C"
import (
    "context"
    "encoding/json"
    "fmt"
    "runtime"
    "sync"
    "syscall"
    "unsafe"

    box "github.com/sagernet/sing-box"
    "github.com/sagernet/sing-box/option"
)

// 全局状态与回调（线程安全）
var (
    instance    *box.Box
    mu          sync.Mutex
    ctx         context.Context
    cancel      context.CancelFunc
    logCallback func(string)
    lastError   string // 最近一次错误字符串，供 Dart 侧读取
)

// 备注：如需桥接 sing-box 内部日志，可在此处按需接入其日志接口。

// 记录错误并可供 Dart 侧获取
func setLastError(err error) {
    if err == nil {
        lastError = ""
        return
    }
    lastError = err.Error()
}

// 尝试预加载 Wintun（仅 Windows，有助于尽早发现依赖缺失）
func tryPreloadWintun() {
    if runtime.GOOS != "windows" {
        return
    }
    // 尝试加载同目录或系统路径中的 wintun.dll；失败不致命，由 sing-tun 内部再报错
    if _, err := syscall.LoadDLL("wintun.dll"); err != nil {
        // 仅记录到 lastError 以便 Dart 获取详细诊断
        setLastError(fmt.Errorf("预加载 wintun.dll 失败: %v", err))
    }
}

//export InitSingBox
func InitSingBox() int {
    mu.Lock()
    defer mu.Unlock()

    ctx, cancel = context.WithCancel(context.Background())
    tryPreloadWintun()
    setLastError(nil)
    return 0
}

//export SetLogCallback
func SetLogCallback(callback func(string)) {
    logCallback = callback
}

//export StartSingBox
func StartSingBox(configJSON *C.char) int {
    mu.Lock()
    defer mu.Unlock()

    if instance != nil {
        return -1 // 已在运行
    }

    // 解析配置
    var options option.Options
    configStr := C.GoString(configJSON)
    if err := json.Unmarshal([]byte(configStr), &options); err != nil {
        setLastError(fmt.Errorf("配置解析失败: %w", err))
        if logCallback != nil {
            logCallback(fmt.Sprintf("配置解析失败: %v", err))
        }
        return -2
    }

    // 创建 sing-box 实例
    var err error
    instance, err = box.New(box.Options{
        Context: ctx,
        Options: options,
    })
    if err != nil {
        setLastError(fmt.Errorf("创建实例失败: %w", err))
        if logCallback != nil {
            logCallback(fmt.Sprintf("创建实例失败: %v", err))
        }
        return -3
    }

    // 启动服务
    err = instance.Start()
    if err != nil {
        setLastError(fmt.Errorf("启动失败: %w", err))
        if logCallback != nil {
            logCallback(fmt.Sprintf("启动失败: %v", err))
        }
        instance = nil
        return -4
    }

    setLastError(nil)
    if logCallback != nil {
        logCallback("sing-box 启动成功")
    }
    return 0
}

//export StopSingBox
func StopSingBox() int {
    mu.Lock()
    defer mu.Unlock()

    if instance == nil {
        return -1 // 未运行
    }

    err := instance.Close()
    if err != nil {
        setLastError(fmt.Errorf("停止失败: %w", err))
        if logCallback != nil {
            logCallback(fmt.Sprintf("停止失败: %v", err))
        }
        return -2
    }

    instance = nil
    setLastError(nil)
    if logCallback != nil {
        logCallback("sing-box 已停止")
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
    if err := json.Unmarshal([]byte(configStr), &options); err != nil {
        setLastError(fmt.Errorf("配置无效: %w", err))
        if logCallback != nil {
            logCallback(fmt.Sprintf("配置无效: %v", err))
        }
        return -1
    }
    setLastError(nil)
    if logCallback != nil {
        logCallback("配置验证通过")
    }
    return 0
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
    setLastError(nil)
}

// 导出版本与错误获取给 Dart 侧（匹配 singbox_ffi.dart 绑定）

//export GetVersion
func GetVersion() *C.char {
    // 简单版本信息，可按需扩展
    ver := "sing-box DLL (WinTUN-enabled)"
    return C.CString(ver)
}

//export SbGetLastError
func SbGetLastError() *C.char {
    if lastError == "" {
        return nil
    }
    return C.CString(lastError)
}

//export FreeCString
func FreeCString(p *C.char) {
    if p != nil {
        C.free(unsafe.Pointer(p))
    }
}

func main() {
    // 必须存在但不会被调用
}
