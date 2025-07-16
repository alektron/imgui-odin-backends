package Platform

import win32 "core:sys/windows"

ThreadSleep :: proc(milliseconds: u32) {
  win32.Sleep(milliseconds)
}