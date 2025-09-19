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
	"crypto/tls"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
	"time"
	"unsafe"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"

	// 使用 sagernet fork 的 quic-go
	quic "github.com/sagernet/quic-go"
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
var lastRestartAt time.Time

// 记录当前运行配置与动态插入的路由规则（JSON 文本形式）
// pristineConfigJSON 记录“无临时规则”的基线配置
var baseConfigJSON string
var currentConfigJSON string
var dynamicRuleJSONs []string

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
	// 同时输出到标准输出，便于在控制台查看（若有）
	fmt.Println(fmt.Sprintf("%s [NATIVE] %s", timestamp(), msg))
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
	} else {
		// 无回调时，直接输出到标准输出，便于开发时在终端/调试器看到
		fmt.Println(message)
	}
}

//export InitSingBox
func InitSingBox() int {
	mu.Lock()
	defer mu.Unlock()
	dbg("InitSingBox enter")

	if cancel != nil {
		cancel()
	}
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

	if ctx == nil {
		// 容忍未显式调用 InitSingBox 的情况
		ctx, cancel = context.WithCancel(context.Background())
	}

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
	// 刷新基线配置：每次 Start 都将当前传入配置作为新的基线
	baseConfigJSON = configStr
	currentConfigJSON = configStr
	dynamicRuleJSONs = nil
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

	dbg("->StopSingBox enter prelock")
	// 先获取锁检查状态，并在关闭前尽早传播取消信号，避免 Close 阻塞于网络/DNS 超时
	mu.Lock()
	if instance == nil {
		if logCB != nil {
			msg := C.CString("sing-box 未运行")
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		mu.Unlock()
		return -1 // 未运行
	}

	// 提前取消 context，帮助打断正在进行的拨号/请求/解析
	if cancel != nil {
		cancel()
		cancel = nil
	}
	// 保存当前实例引用，释放锁后再执行可能耗时的 Close
	i := instance
	mu.Unlock()

	// 执行优雅关闭（不持锁，避免阻塞其它调用）
	err := i.Close()
	if err != nil {
		if logCB != nil {
			msg := C.CString(fmt.Sprintf("停止失败: %v", err))
			C.callLog(logCB, msg)
			C.free(unsafe.Pointer(msg))
		}
		return -2
	}

	// 关闭完成后，清理全局状态
	mu.Lock()
	instance = nil
	// 停止后清空当前与基线配置，等待下次 Start 设置
	currentConfigJSON = ""
	baseConfigJSON = ""
	// 为后续 Start 重新准备一个新的可取消上下文
	ctx, cancel = context.WithCancel(context.Background())
	mu.Unlock()

	if logCB != nil {
		msg := C.CString("sing-box 已停止")
		C.callLog(logCB, msg)
		C.free(unsafe.Pointer(msg))
	}
	dbg("->StopSingBox leave success")

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
	// 先取消 context，尽快打断后台操作
	if cancel != nil {
		cancel()
		cancel = nil
	}
	i := instance
	instance = nil
	// 清理配置记录
	baseConfigJSON = ""
	currentConfigJSON = ""
	dynamicRuleJSONs = nil
	mu.Unlock()

	// 在不持锁状态下关闭实例，避免阻塞其它调用
	if i != nil {
		_ = i.Close()
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

// --- 动态路由规则：通过合并配置并平滑重启实现（注意：会短暂中断现有连接） ---

// 合并 baseConfigJSON + dynamicRuleJSONs 到一个新的配置 JSON
func buildMergedConfig() (string, error) {
	if baseConfigJSON == "" {
		return "", fmt.Errorf("no base config available")
	}
	// 解析为通用 map 以便操作 route.rules
	var base map[string]interface{}
	if err := sjson.Unmarshal([]byte(baseConfigJSON), &base); err != nil {
		// 尝试使用 currentConfigJSON 作为兜底
		if currentConfigJSON != "" {
			if err2 := sjson.Unmarshal([]byte(currentConfigJSON), &base); err2 == nil {
				goto MERGE_RULES
			}
		}
		return "", fmt.Errorf("unmarshal base: %w", err)
	}
MERGE_RULES:
	route, ok := base["route"].(map[string]interface{})
	if !ok {
		route = map[string]interface{}{}
		base["route"] = route
	}
	// 取出现有 rules
	var rules []interface{}
	if v, ok := route["rules"].([]interface{}); ok {
		rules = v
	} else {
		rules = []interface{}{}
	}
	// 把动态规则插入到最前面（高优先级）
	for i := len(dynamicRuleJSONs) - 1; i >= 0; i-- { // 逆序插入保持调用顺序
		rjs := dynamicRuleJSONs[i]
		var r map[string]interface{}
		if err := sjson.Unmarshal([]byte(rjs), &r); err != nil {
			return "", fmt.Errorf("bad rule json: %w", err)
		}
		rules = append([]interface{}{r}, rules...)
	}
	route["rules"] = rules
	mergedBytes, err := sjson.Marshal(base)
	if err != nil {
		return "", fmt.Errorf("marshal merged: %w", err)
	}
	return string(mergedBytes), nil
}

func restartWithConfig(cfg string) error {
	// 简单节流：两次重启间隔至少 300ms，避免频繁操作导致卡顿
	if !lastRestartAt.IsZero() {
		delta := time.Since(lastRestartAt)
		if delta < 300*time.Millisecond {
			time.Sleep(300*time.Millisecond - delta)
		}
	}
	// 若未运行，直接使用 cfg 启动
	if instance == nil {
		conf := C.CString(cfg)
		defer C.free(unsafe.Pointer(conf))
		r := StartSingBox(conf)
		if r != 0 && r != -1 { // -1 表示已在运行，不应发生
			return fmt.Errorf("start failed code=%d", r)
		}
		return nil
	}
	// 运行中：先关闭再用新配置启动
	if err := instance.Close(); err != nil {
		return fmt.Errorf("close: %w", err)
	}
	instance = nil

	// 解析与创建
	var options option.Options
	ctxWithRegistry := include.Context(ctx)
	if err := sjson.UnmarshalContext(ctxWithRegistry, []byte(cfg), &options); err != nil {
		return fmt.Errorf("parse options: %w", err)
	}
	var pw log.PlatformWriter
	if logCB != nil {
		pw = &ffiPlatformWriter{}
	}
	b, err := box.New(box.Options{Context: ctxWithRegistry, Options: options, PlatformLogWriter: pw})
	if err != nil {
		return fmt.Errorf("box.New: %w", err)
	}
	if err := b.Start(); err != nil {
		return fmt.Errorf("instance.Start: %w", err)
	}
	instance = b
	currentConfigJSON = cfg
	lastRestartAt = time.Now()
	return nil
}

//export AddRouteRule
func AddRouteRule(ruleJSON *C.char) int {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		setLastError(fmt.Errorf("not running"))
		return -1
	}
	r := C.GoString(ruleJSON)
	// 先验证是合法 JSON
	var tmp map[string]interface{}
	if err := sjson.Unmarshal([]byte(r), &tmp); err != nil {
		setLastError(fmt.Errorf("invalid rule json: %w", err))
		return -2
	}
	// 仅更新内存，并由 ReloadConfig 统一触发一次重启
	dynamicRuleJSONs = append(dynamicRuleJSONs, r)
	return 0
}

//export RemoveRouteRule
func RemoveRouteRule(ruleJSON *C.char) int {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		setLastError(fmt.Errorf("not running"))
		return -1
	}
	r := C.GoString(ruleJSON)
	// 删除匹配的第一项
	idx := -1
	for i, v := range dynamicRuleJSONs {
		if v == r {
			idx = i
			break
		}
	}
	if idx < 0 {
		setLastError(fmt.Errorf("rule not found"))
		return -2
	}
	// 仅更新内存，并由 ReloadConfig 统一触发一次重启
	dynamicRuleJSONs = append(dynamicRuleJSONs[:idx], dynamicRuleJSONs[idx+1:]...)
	return 0
}

//export ReloadConfig
func ReloadConfig() int {
	mu.Lock()
	if instance == nil {
		mu.Unlock()
		setLastError(fmt.Errorf("not running"))
		return -1
	}
	merged, err := buildMergedConfig()
	mu.Unlock()
	if err != nil {
		setLastError(err)
		return -2
	}
	if err := restartWithConfig(merged); err != nil {
		setLastError(err)
		return -3
	}
	return 0
}

//export ReplaceConfig
func ReplaceConfig(configJSON *C.char) int {
	// 更新基线配置并以此重启（保留动态规则），用于在线热切换节点
	if configJSON == nil {
		setLastError(fmt.Errorf("nil config"))
		return -4
	}
	newCfg := C.GoString(configJSON)

	// 先更新内存中的基线配置
	mu.Lock()
	if instance == nil {
		mu.Unlock()
		setLastError(fmt.Errorf("not running"))
		return -1
	}
	baseConfigJSON = newCfg
	currentConfigJSON = newCfg
	mu.Unlock()

	// 合并动态规则并执行重启
	merged, err := buildMergedConfig()
	if err != nil {
		setLastError(err)
		return -2
	}
	if err := restartWithConfig(merged); err != nil {
		setLastError(err)
		return -3
	}
	return 0
}

//export ClearRouteRules
func ClearRouteRules() int {
	mu.Lock()
	defer mu.Unlock()
	dynamicRuleJSONs = nil
	return 0
}

func main() {
	// 这个函数需要存在，但不会被调用
}

// ====================== 额外：严格探测（TLS/QUIC 最小握手） ======================

func parseALPN(csv string) []string {
	csv = strings.TrimSpace(csv)
	if csv == "" {
		return nil
	}
	parts := strings.Split(csv, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

//export ProbeTLS
func ProbeTLS(host *C.char, port C.int, sni *C.char, insecure C.int, alpnCsv *C.char, timeoutMs C.int) C.int {
	h := C.GoString(host)
	p := int(port)
	addr := fmt.Sprintf("%s:%d", h, p)
	serverName := C.GoString(sni)
	alpn := parseALPN(C.GoString(alpnCsv))
	dialer := &net.Dialer{Timeout: time.Duration(int(timeoutMs)) * time.Millisecond}
	tlsConf := &tls.Config{ServerName: serverName, InsecureSkipVerify: insecure != 0}
	if len(alpn) > 0 {
		tlsConf.NextProtos = alpn
	}
	conn, err := tls.DialWithDialer(dialer, "tcp", addr, tlsConf)
	if err != nil {
		setLastError(fmt.Errorf("tls probe: %w", err))
		return -1
	}
	_ = conn.Close()
	return 0
}

//export ProbeQUIC
func ProbeQUIC(host *C.char, port C.int, sni *C.char, insecure C.int, alpnCsv *C.char, timeoutMs C.int) C.int {
	h := C.GoString(host)
	p := int(port)
	addr := fmt.Sprintf("%s:%d", h, p)
	serverName := C.GoString(sni)
	alpn := parseALPN(C.GoString(alpnCsv))
	if len(alpn) == 0 {
		// 兜底：提供常见的 QUIC ALPN，提升握手成功率
		alpn = []string{"h3", "tuic"}
	}
	tlsConf := &tls.Config{ServerName: serverName, InsecureSkipVerify: insecure != 0, NextProtos: alpn}
	qconf := &quic.Config{}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(int(timeoutMs))*time.Millisecond)
	defer cancel()
	conn, err := quic.DialAddr(ctx, addr, tlsConf, qconf)
	if err != nil {
		setLastError(fmt.Errorf("quic probe: %w", err))
		return -1
	}
	// 用 0 错误码关闭
	_ = conn.CloseWithError(0, "probe")
	return 0
}
