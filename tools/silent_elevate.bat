@echo off
:: 静默提权脚本 - 用于启动需要管理员权限的操作
:: 用法: silent_elevate.bat <程序路径> [参数...]

:: 获取要执行的命令
set command=%1
:: 移除引号
set command=%command:"=%
set args=%2

:: 循环获取所有参数
:param
if "%3"=="" (
    goto end
)
set args=%args% %3
shift /0
goto param

:end
:: 使用 mshta + vbscript 实现静默提权
:: shellexecute 参数说明：
:: - command: 要执行的程序
:: - args: 程序参数
:: - "": 工作目录（空=当前目录）
:: - "runas": 以管理员权限运行
:: - 0: 隐藏窗口（1=正常窗口）
mshta vbscript:createobject("shell.application").shellexecute("%command%","%args%","","runas",0)(window.close)