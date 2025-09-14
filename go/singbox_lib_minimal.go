package main

import "C"
import (
	"context"
	"encoding/json"
	"sync"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/option"
)

var (
	instance *box.Box
	mu       sync.Mutex
	ctx      context.Context
	cancel   context.CancelFunc
)

//export InitSingBox
func InitSingBox() int {
	mu.Lock()
	defer mu.Unlock()

	ctx, cancel = context.WithCancel(context.Background())
	return 0
}

//export StartSingBox
func StartSingBox(configJSON *C.char) int {
	mu.Lock()
	defer mu.Unlock()

	if instance != nil {
		return -1 // 已经在运行
	}

	// 解析配置
	var options option.Options
	configStr := C.GoString(configJSON)
	if err := json.Unmarshal([]byte(configStr), &options); err != nil {
		return -2
	}

	// 创建 sing-box 实例
	var err error
	instance, err = box.New(box.Options{
		Context: ctx,
		Options: options,
	})

	if err != nil {
		return -3
	}

	// 启动服务
	err = instance.Start()
	if err != nil {
		instance = nil
		return -4
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
		return -2
	}

	instance = nil
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
		return -1
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
}

func main() {
	// 这个函数需要存在，但不会被调用
}