package Platform

import win32 "core:sys/windows"

MouseButton :: enum {
  LEFT,
  MIDDLE,
  RIGHT
}

MouseCursor :: enum {
  NONE,
  ARROW,
  TEXT_INPUT,         // When hovering over InputText, etc.
  RESIZE_NS,          // When hovering over an horizontal border
  RESIZE_EW,          // When hovering over a vertical border or a column
  RESIZE_NESW,        // When hovering over the bottom-left corner of a window
  RESIZE_NWSE,        // When hovering over the bottom-right corner of a window
  NOT_ALLOWED,        // When hovering something with disallowed interaction. Usually a crossed circle.
  HAND, 
  RESIZE_ALL,
};

@(private="file")
gMouseCursors: [MouseCursor]win32.HCURSOR

InputInit :: proc() {
  gMouseCursors[.ARROW      ] = win32.LoadCursorA(nil, win32.IDC_ARROW)
  gMouseCursors[.TEXT_INPUT ] = win32.LoadCursorA(nil, win32.IDC_IBEAM)
  gMouseCursors[.RESIZE_NS  ] = win32.LoadCursorA(nil, win32.IDC_SIZENS)
  gMouseCursors[.RESIZE_EW  ] = win32.LoadCursorA(nil, win32.IDC_SIZEWE)
  gMouseCursors[.RESIZE_NESW] = win32.LoadCursorA(nil, win32.IDC_SIZENESW)
  gMouseCursors[.RESIZE_NWSE] = win32.LoadCursorA(nil, win32.IDC_SIZENWSE)
  gMouseCursors[.NOT_ALLOWED] = win32.LoadCursorA(nil, win32.IDC_NO)
  gMouseCursors[.HAND       ] = win32.LoadCursorA(nil, win32.IDC_HAND)
  gMouseCursors[.RESIZE_ALL ] = win32.LoadCursorA(nil, win32.IDC_SIZEALL)
}

InternalFromMouseButton :: proc(button : MouseButton) -> i32 {
  switch button {
    case .LEFT  : return win32.VK_LBUTTON
    case .RIGHT : return win32.VK_RBUTTON
    case .MIDDLE: return win32.VK_MBUTTON
  }

  return 0
}

IsMouseButtonDown :: proc(button : MouseButton = .LEFT) -> bool {
  return win32.GetKeyState(InternalFromMouseButton(button)) < 0
}

GetMousePosScreen :: proc() -> [2]f32 {
  p : win32.POINT
  win32.GetCursorPos(&p)
  return { f32(p.x), f32(p.y) }
}

GetMousePosWindow :: proc(window : Window) -> [2]f32 {
  p : win32.POINT
  win32.GetCursorPos(&p)
  win32.ScreenToClient(window.Handle, &p)
  return { f32(p.x), f32(p.y) }
}

SetMouseCursor :: proc(cursor: MouseCursor) {
  win32.SetCursor(gMouseCursors[cursor])
}

GetClipboardText :: proc(allocator := context.temp_allocator) -> string {
  if !win32.IsClipboardFormatAvailable(win32.CF_UNICODETEXT) do return {}
  if !win32.OpenClipboard(nil) do return {}
  defer win32.CloseClipboard()
  
  clipboardData := win32.HGLOBAL(win32.GetClipboardData(win32.CF_UNICODETEXT))
  str := (win32.wstring)(win32.GlobalLock(clipboardData))
  defer win32.GlobalUnlock(clipboardData)
  
  wstrlen :: proc(str: win32.wstring) -> int {
    i := 0
    for ; str[i] != 0; i += 1 {}
    return i
  }
  
  return win32.wstring_to_utf8(str, wstrlen(str), allocator) or_else {}
}

SetClipboardText :: proc(text: string) -> bool {
  if !win32.OpenClipboard(nil) do return false
  defer win32.CloseClipboard()
  
  wtext := win32.utf8_to_utf16(text)
  global := win32.HGLOBAL(win32.GlobalAlloc(win32.GMEM_MOVEABLE, (len(wtext) + 1) * size_of(wtext[0])))
  if global == nil do return false
  
  wbuf := win32.wstring(win32.GlobalLock(global))
  defer win32.GlobalUnlock(global)
  
  copy(wbuf[:len(wtext)], wtext)
  wbuf[len(wtext) + 1] = 0
  
  win32.EmptyClipboard()
  if win32.SetClipboardData(win32.CF_UNICODETEXT, win32.HANDLE(global)) == nil {
    win32.GlobalFree(global)
    return false
  }
  
  return true
}

Key :: enum {
  NONE = 0,
  
  A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
  
  //Number keys (regular, not num-pad)
  N0, N1, N2, N3, N4, N5, N6, N7, N8, N9,
   
  F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
  F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24,
  
  NUMPAD_0, NUMPAD_1, NUMPAD_2, NUMPAD_3, NUMPAD_4, NUMPAD_5, NUMPAD_6, NUMPAD_7, NUMPAD_8, NUMPAD_9,
  NUM_MULTIPLY, NUM_ADD, NUM_SUBTRACT, NUM_DECIMAL, NUM_DIVIDE, NUM_LOCK, //NUM_ENTER,
  
  ESCAPE, PRINT, SCROLL_LOCK, PAUSE,
  INSERT, DELETE, HOME, END, PAGE_UP, PAGE_DOWN,
  
  ARROW_LEFT, ARROW_RIGHT, ARROW_UP, ARROW_DOWN,
  
  SPACE, ENTER, BACKSPACE,
  
  CTRL_L, CTRL_R, SHIFT_L, SHIFT_R, ALT_L, ALT_R, WIN_L, WIN_R, CAPS_LOCK, TAB,
  
  COMMA, PERIOD, APOSTROPHE, MINUS, SLASH, BACKSLASH, SEMICOLON, EQUAL, BRACKET_L, BRACKET_R, ACCENT_GRAVE,
  
  _CTRL, _SHIFT, _ALT,
}

//Converts our platform agnostic Key type into a platform key code.
InternalFromKey :: proc(key : Key) -> i32 {
  switch key {
    case .A: return win32.VK_A
    case .B: return win32.VK_B
    case .C: return win32.VK_C
    case .D: return win32.VK_D
    case .E: return win32.VK_E
    case .F: return win32.VK_F
    case .G: return win32.VK_G
    case .H: return win32.VK_H
    case .I: return win32.VK_I
    case .J: return win32.VK_J
    case .K: return win32.VK_K
    case .L: return win32.VK_L
    case .M: return win32.VK_M
    case .N: return win32.VK_N
    case .O: return win32.VK_O
    case .P: return win32.VK_P
    case .Q: return win32.VK_Q
    case .R: return win32.VK_R
    case .S: return win32.VK_S
    case .T: return win32.VK_T
    case .U: return win32.VK_U
    case .V: return win32.VK_V
    case .W: return win32.VK_W
    case .X: return win32.VK_X
    case .Y: return win32.VK_Y
    case .Z: return win32.VK_Z
    
    case .N0: return 0x30
    case .N1: return 0x31
    case .N2: return 0x32
    case .N3: return 0x33
    case .N4: return 0x34
    case .N5: return 0x35
    case .N6: return 0x36
    case .N7: return 0x37
    case .N8: return 0x38
    case .N9: return 0x39
    
    case .F1 : return 0x70
    case .F2 : return 0x71
    case .F3 : return 0x72
    case .F4 : return 0x73
    case .F5 : return 0x74
    case .F6 : return 0x75
    case .F7 : return 0x76
    case .F8 : return 0x77
    case .F9 : return 0x78
    case .F10: return 0x79
    case .F11: return 0x7A
    case .F12: return 0x7B
    case .F13: return 0x7C
    case .F14: return 0x7D
    case .F15: return 0x7E
    case .F16: return 0x7F
    case .F17: return 0x80
    case .F18: return 0x81
    case .F19: return 0x82
    case .F20: return 0x83
    case .F21: return 0x84
    case .F22: return 0x85
    case .F23: return 0x86
    case .F24: return 0x87
    
    case .NUMPAD_0: return win32.VK_NUMPAD0
    case .NUMPAD_1: return win32.VK_NUMPAD1
    case .NUMPAD_2: return win32.VK_NUMPAD2
    case .NUMPAD_3: return win32.VK_NUMPAD3
    case .NUMPAD_4: return win32.VK_NUMPAD4
    case .NUMPAD_5: return win32.VK_NUMPAD5
    case .NUMPAD_6: return win32.VK_NUMPAD6
    case .NUMPAD_7: return win32.VK_NUMPAD7
    case .NUMPAD_8: return win32.VK_NUMPAD8
    case .NUMPAD_9: return win32.VK_NUMPAD9
    
    case .NUM_MULTIPLY: return win32.VK_MULTIPLY
    case .NUM_ADD     : return win32.VK_ADD
    case .NUM_SUBTRACT: return win32.VK_SUBTRACT
    case .NUM_DECIMAL : return win32.VK_DECIMAL
    case .NUM_DIVIDE  : return win32.VK_DIVIDE
    case .NUM_LOCK    : return win32.VK_NUMLOCK
    //case .NUM_ENTER   : return VK_
    
    case .ESCAPE: return win32.VK_ESCAPE
    case .PRINT : return win32.VK_PRINT
    case .PAUSE : return win32.VK_PAUSE
    case .SCROLL_LOCK: return win32.VK_SCROLL
    
    case .INSERT   : return win32.VK_INSERT
    case .DELETE   : return win32.VK_DELETE
    case .HOME     : return win32.VK_HOME
    case .END      : return win32.VK_END
    case .PAGE_UP  : return win32.VK_PRIOR
    case .PAGE_DOWN: return win32.VK_NEXT
    
    case .ARROW_LEFT : return win32.VK_LEFT
    case .ARROW_RIGHT: return win32.VK_RIGHT
    case .ARROW_UP   : return win32.VK_UP
    case .ARROW_DOWN : return win32.VK_DOWN
    
    case .SPACE    : return win32.VK_SPACE
    case .ENTER    : return win32.VK_RETURN
    case .BACKSPACE: return win32.VK_BACK
    
    case .TAB: return win32.VK_TAB
    case .CAPS_LOCK: return win32.VK_CAPITAL
    
    case .COMMA       : return win32.VK_OEM_COMMA
    case .PERIOD      : return win32.VK_OEM_PERIOD
    case .APOSTROPHE  : return win32.VK_OEM_7
    case .MINUS       : return win32.VK_OEM_MINUS
    case .SLASH       : return win32.VK_OEM_2
    case .BACKSLASH   : return win32.VK_OEM_5
    case .SEMICOLON   : return win32.VK_OEM_1
    case .EQUAL       : return win32.VK_OEM_PLUS
    case .BRACKET_L   : return win32.VK_OEM_4
    case .BRACKET_R   : return win32.VK_OEM_6
    case .ACCENT_GRAVE: return win32.VK_OEM_3
    
    case .CTRL_L : return win32.VK_LCONTROL
    case .CTRL_R : return win32.VK_RCONTROL
    case .SHIFT_L: return win32.VK_LSHIFT
    case .SHIFT_R: return win32.VK_RSHIFT
    case .ALT_L  : return win32.VK_LMENU
    case .ALT_R  : return win32.VK_RMENU
    case .WIN_L  : return win32.VK_LWIN
    case .WIN_R  : return win32.VK_RWIN
    
    case ._CTRL : return win32.VK_CONTROL
    case ._SHIFT: return win32.VK_SHIFT
    case ._ALT  : return win32.VK_MENU
    
    case .NONE: return 0
  }
  return 0
}


//Converts the platform key codes into our platform agnostic Key type.
//It gets extended whenever necessary.
KeyFromInternal :: proc(key : i32) -> Key {
  switch key {
    case win32.VK_A: return .A
    case win32.VK_B: return .B
    case win32.VK_C: return .C
    case win32.VK_D: return .D
    case win32.VK_E: return .E
    case win32.VK_F: return .F
    case win32.VK_G: return .G
    case win32.VK_H: return .H
    case win32.VK_I: return .I
    case win32.VK_J: return .J
    case win32.VK_K: return .K
    case win32.VK_L: return .L
    case win32.VK_M: return .M
    case win32.VK_N: return .N
    case win32.VK_O: return .O
    case win32.VK_P: return .P
    case win32.VK_Q: return .Q
    case win32.VK_R: return .R
    case win32.VK_S: return .S
    case win32.VK_T: return .T
    case win32.VK_U: return .U
    case win32.VK_V: return .V
    case win32.VK_W: return .W
    case win32.VK_X: return .X
    case win32.VK_Y: return .Y
    case win32.VK_Z: return .Z
    
    case 0x30: return .N0
    case 0x31: return .N1
    case 0x32: return .N2
    case 0x33: return .N3
    case 0x34: return .N4
    case 0x35: return .N5
    case 0x36: return .N6
    case 0x37: return .N7
    case 0x38: return .N8
    case 0x39: return .N9
    
    case 0x70: return .F1 
    case 0x71: return .F2 
    case 0x72: return .F3 
    case 0x73: return .F4 
    case 0x74: return .F5 
    case 0x75: return .F6 
    case 0x76: return .F7 
    case 0x77: return .F8 
    case 0x78: return .F9 
    case 0x79: return .F10
    case 0x7A: return .F11
    case 0x7B: return .F12
    case 0x7C: return .F13
    case 0x7D: return .F14
    case 0x7E: return .F15
    case 0x7F: return .F16
    case 0x80: return .F17
    case 0x81: return .F18
    case 0x82: return .F19
    case 0x83: return .F20
    case 0x84: return .F21
    case 0x85: return .F22
    case 0x86: return .F23
    case 0x87: return .F24
    
    case win32.VK_NUMPAD0: return .NUMPAD_0
    case win32.VK_NUMPAD1: return .NUMPAD_1
    case win32.VK_NUMPAD2: return .NUMPAD_2
    case win32.VK_NUMPAD3: return .NUMPAD_3
    case win32.VK_NUMPAD4: return .NUMPAD_4
    case win32.VK_NUMPAD5: return .NUMPAD_5
    case win32.VK_NUMPAD6: return .NUMPAD_6
    case win32.VK_NUMPAD7: return .NUMPAD_7
    case win32.VK_NUMPAD8: return .NUMPAD_8
    case win32.VK_NUMPAD9: return .NUMPAD_9
    
    case win32.VK_MULTIPLY: return .NUM_MULTIPLY
    case win32.VK_ADD     : return .NUM_ADD     
    case win32.VK_SUBTRACT: return .NUM_SUBTRACT
    case win32.VK_DECIMAL : return .NUM_DECIMAL 
    case win32.VK_DIVIDE  : return .NUM_DIVIDE  
    case win32.VK_NUMLOCK : return .NUM_LOCK    
    //case .NUM_ENTER   : return VK_
    
    case win32.VK_ESCAPE: return .ESCAPE
    case win32.VK_PRINT : return .PRINT 
    case win32.VK_PAUSE : return .PAUSE 
    case win32.VK_SCROLL: return .SCROLL_LOCK
    
    case win32.VK_INSERT: return .INSERT        
    case win32.VK_DELETE: return .DELETE        
    case win32.VK_HOME  : return .HOME        
    case win32.VK_END   : return .END        
    case win32.VK_PRIOR : return .PAGE_UP      
    case win32.VK_NEXT  : return .PAGE_DOWN   
         
    case win32.VK_LEFT : return .ARROW_LEFT     
    case win32.VK_RIGHT: return .ARROW_RIGHT     
    case win32.VK_UP   : return .ARROW_UP     
    case win32.VK_DOWN : return .ARROW_DOWN     
         
    case win32.VK_SPACE : return .SPACE
    case win32.VK_RETURN: return .ENTER         
    case win32.VK_BACK  : return .BACKSPACE   
         
    case win32.VK_TAB : return .TAB          
    case win32.VK_CAPITAL: return .CAPS_LOCK     
         
    case win32.VK_OEM_COMMA : return .COMMA       
    case win32.VK_OEM_PERIOD: return .PERIOD       
    case win32.VK_OEM_7     : return .APOSTROPHE  
    case win32.VK_OEM_MINUS : return .MINUS           
    case win32.VK_OEM_2     : return .SLASH       
    case win32.VK_OEM_5     : return .BACKSLASH   
    case win32.VK_OEM_1     : return .SEMICOLON   
    case win32.VK_OEM_PLUS  : return .EQUAL          
    case win32.VK_OEM_4     : return .BRACKET_L   
    case win32.VK_OEM_6     : return .BRACKET_R   
    case win32.VK_OEM_3     : return .ACCENT_GRAVE
         
    case win32.VK_LCONTROL: return .CTRL_L      
    case win32.VK_RCONTROL: return .CTRL_R      
    case win32.VK_LSHIFT  : return .SHIFT_L   
    case win32.VK_RSHIFT  : return .SHIFT_R   
    case win32.VK_LMENU   : return .ALT_L    
    case win32.VK_RMENU   : return .ALT_R    
    case win32.VK_LWIN    : return .WIN_L   
    case win32.VK_RWIN    : return .WIN_R
    
    case win32.VK_CONTROL: return ._CTRL
    case win32.VK_SHIFT  : return ._SHIFT     
    case win32.VK_MENU   : return ._ALT      
  }
  
  return .NONE
}

IsKeyPressed :: proc(key : Key) -> bool {
  return win32.GetKeyState(InternalFromKey(key)) < 0
}