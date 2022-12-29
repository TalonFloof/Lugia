module main

[export: "show_alert"]
pub fn show_alert(msg string) {
	panic(msg)
}

pub fn open_file() string {
	println("Usage: Lugia <GameBoy ROM>")
	exit(0)
	return ""
}