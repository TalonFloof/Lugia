module main

#include <Cocoa/Cocoa.h>
#flag -framework Cocoa

#include "@VROOT/utils_darwin.m"

fn C.internal_open_file() string

fn C.internal_show_alert(s string)

[export: 'show_alert']
pub fn show_alert(msg string) {
	C.internal_show_alert(msg)
	panic(msg)
}

[export: 'open_file']
pub fn open_file() string {
	return C.internal_open_file()
}