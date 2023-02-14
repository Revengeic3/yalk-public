package logger

import (
	"fmt"
)

var Reset = "\033[0m"
var Red = "\033[31m"
var Green = "\033[32m"
var Yellow = "\033[33m"
var Blue = "\033[34m"
var Purple = "\033[35m"
var Cyan = "\033[36m"
var Gray = "\033[37m"
var BrightRed = "\033[91m"
var BrightGreen = "\033[92m"
var BrightYellow = "\033[93m"
var BrightBlue = "\033[94m"
var BrightPurple = "\033[95m"
var Orange = "\033[96m"
var White = "\033[97m"

func LogColor(component string, message string) {
	// if runtime.GOOS == "windows" {
	// 	Reset = ""
	// 	Red = `$host.UI.RawUI.ForegroundColor = "Red"`
	// 	Green = `$host.UI.RawUI.ForegroundColor = "Green"`
	// 	Yellow = `$host.UI.RawUI.ForegroundColor = "Yellow"`
	// 	Blue = `$host.UI.RawUI.ForegroundColor = "Blue"`
	// 	Purple = `$host.UI.RawUI.ForegroundColor = "Purplle"`
	// 	Cyan = `$host.UI.RawUI.ForegroundColor = "Cyan"`
	// 	Gray = `$host.UI.RawUI.ForegroundColor = "Gray"`
	// 	White = `$host.UI.RawUI.ForegroundColor = "White"`
	// }
	switch component {
	// ! This must be done better..
	// ? calulcate string and key lenght and put space based on that..?
	case "CORE":
		color := Green
		fmt.Printf("%s[%s]%s    |  %s\n", color, component, Reset, message)
	case "WEBSRV":
		color := BrightPurple
		fmt.Printf("%s[%s]%s  |  %s\n", color, component, Reset, message)
	case "SSE":
		color := BrightYellow
		fmt.Printf("%s[%s]%s     |  %s\n", color, component, Reset, message)
	case "HTTP":
		color := Blue
		fmt.Printf("%s[%s]%s    |  %s\n", color, component, Reset, message)
	case "SESSION":
		color := Orange
		fmt.Printf("%s[%s]%s |  %s\n", color, component, Reset, message)
	case "DATABASE":
		color := Yellow
		fmt.Printf("%s[%s]%s |  %s\n", color, component, Reset, message)
	case "SOCKET":
		color := Purple
		fmt.Printf("%s[%s]%s  |  %s\n", color, component, Reset, message)
	case "WEBSOCK":
		color := Red
		fmt.Printf("%s[%s]%s |  %s\n", color, component, Reset, message)
	case "API":
		color := Cyan
		fmt.Printf("%s[%s]%s     |  %s\n", color, component, Reset, message)
	default:
		color := White
		fmt.Printf("%s[%s]%s  |  %s\n", color, component, Reset, message)
	}
}
