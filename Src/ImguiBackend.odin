package main
import "core:c"
import "core:slice"
import "base:runtime"

import "../Libraries/imgui"

import "Platform"

ClipboardContext :: struct {
  Context: runtime.Context,
  Buffer: [dynamic]u8,
}

ImGuiBackend :: struct {
  Context: ^imgui.Context,
  FontAtlas: ^imgui.FontAtlas,
  LastMouseCursor: imgui.MouseCursor,
  Clipboard: ClipboardContext,
}

VertexImGui :: struct {
  Pos : [2]f32,
  Tex : [2]f32,
  Col : u32,
}

@(private="file")
ImGui_FontAtlasInit :: proc(atlas: ^imgui.FontAtlas) {
  //The following fields of imgui.FontAtlas are usually set by its constructor.
  //Since we do not have constructors in Odin and it seems the imgui bindings do not currently offer
  //an alternative init procedure for us to call we write our own 'constructor' here.
  //Note that without this initialization 'FontAtlas_Build' crashes.
  //We should probably open an issue for that: https://gitlab.com/L-4/odin-imgui
  atlas.TexGlyphPadding = 1
  atlas.PackIdMouseCursors = -1
  atlas.PackIdLines = -1
}

ImGui_Init :: proc(ctx: ^ImGuiBackend, fontContent: []u8, gpu: ^Gpu, gpuRes: ^GpuRes)
{
  ctx.FontAtlas = new(imgui.FontAtlas)
  ImGui_FontAtlasInit(ctx.FontAtlas)
  ctx.FontAtlas.FontBuilderIO = imgui.cImFontAtlasGetBuilderForStbTruetype()
  
  glyphRange := imgui.FontAtlas_GetGlyphRangesDefault(ctx.FontAtlas)
  imgui.FontAtlas_AddFontFromMemoryTTF(ctx.FontAtlas, raw_data(fontContent), i32(len(fontContent)), 15, nil, glyphRange)
  imgui.FontAtlas_Build(ctx.FontAtlas)
  
  pixels: ^c.uchar  
  width, height: c.int
  bytesPerPixel: c.int
  imgui.FontAtlas_GetTexDataAsRGBA32(ctx.FontAtlas, &pixels, &width, &height, &bytesPerPixel)
  
  texId := GpuCreateAndUploadTexture(slice.from_ptr((^u8)(pixels), int(width * height * bytesPerPixel)), u32(width), u32(height), u32(bytesPerPixel), gpu, gpuRes)
  imgui.FontAtlas_SetTexID(ctx.FontAtlas, transmute(rawptr)texId)
  
  ctx.Context = imgui.CreateContext(ctx.FontAtlas)
  imgui.SetCurrentContext(ctx.Context)
  
  io := imgui.GetIO()
  io.BackendFlags |= { .RendererHasVtxOffset, .HasMouseCursors }
  io.ConfigFlags |= { .DockingEnable }
  
  ctx.Clipboard = ClipboardContext { Context = context }
  io.ClipboardUserData = &ctx.Clipboard
  io.GetClipboardTextFn = proc "c" (userData: rawptr) -> cstring {
    ctx := (^ClipboardContext)(userData)
    context = ctx.Context
    clipboard := Platform.GetClipboardText()
    if len(ctx.Buffer) < len(clipboard) + 1 {
      resize(&ctx.Buffer, len(clipboard) + 1)
    }
    
    copy(ctx.Buffer[:], clipboard)
    ctx.Buffer[len(clipboard)] = 0
    return cstring(raw_data(ctx.Buffer))
  }
  io.SetClipboardTextFn = proc "c" (userData: rawptr, text: cstring) {
    ctx := (^ClipboardContext)(userData)
    context = ctx.Context
    Platform.SetClipboardText(string(text))
  }
}

ImGui_Free :: proc(ctx: ^ImGuiBackend) {
  delete(ctx.Clipboard.Buffer)
  free(ctx.FontAtlas)
}

ImGui_Events :: proc(events: []Platform.Event) {
  io := imgui.GetIO()
  for ev in events {
    #partial switch e in ev {
      case Platform.EventMouseMove: {
        if .ViewportsEnable in io.ConfigFlags do imgui.IO_AddMousePosEvent(io, e.ScreenPos.x, e.ScreenPos.y)
        else do imgui.IO_AddMousePosEvent(io, e.WindowPos.x, e.WindowPos.y)
      }
      case Platform.EventMouseDown: {
        switch e.Button {
          case .LEFT  : imgui.IO_AddMouseButtonEvent(io, .Left, true)
          case .MIDDLE: imgui.IO_AddMouseButtonEvent(io, .Middle, true)
          case .RIGHT : imgui.IO_AddMouseButtonEvent(io, .Right, true)
        }
      }
      case Platform.EventMouseUp: {
        switch e.Button {
          case .LEFT  : imgui.IO_AddMouseButtonEvent(io, .Left, false)
          case .MIDDLE: imgui.IO_AddMouseButtonEvent(io, .Middle, false)
          case .RIGHT : imgui.IO_AddMouseButtonEvent(io, .Right, false)
        }
      }
      case Platform.EventMouseWheel: {
        if io.WantCaptureMouse {
          imgui.IO_AddMouseWheelEvent(io, e.Delta.x, e.Delta.y)
        }
      }
      case Platform.EventKeyDown: {
        imgui.IO_AddKeyEvent(io, ImGuiKeyFromPlatform(e.Key), true)
        if e.Key == .SHIFT_L || e.Key == .SHIFT_R do imgui.IO_AddKeyEvent(io, .ImGuiMod_Shift, true)
        if e.Key == .CTRL_L  || e.Key == .CTRL_R  do imgui.IO_AddKeyEvent(io, .ImGuiMod_Ctrl , true)
        if e.Key == .ALT_L   || e.Key == .ALT_R   do imgui.IO_AddKeyEvent(io, .ImGuiMod_Alt  , true)
      }
      case Platform.EventKeyUp: {
        imgui.IO_AddKeyEvent(io, ImGuiKeyFromPlatform(e.Key), false)
        if e.Key == .SHIFT_L || e.Key == .SHIFT_R do imgui.IO_AddKeyEvent(io, .ImGuiMod_Shift, false)
        if e.Key == .CTRL_L  || e.Key == .CTRL_R  do imgui.IO_AddKeyEvent(io, .ImGuiMod_Ctrl , false)
        if e.Key == .ALT_L   || e.Key == .ALT_R   do imgui.IO_AddKeyEvent(io, .ImGuiMod_Alt  , false)
      }
      case Platform.EventChar: {
        if io.WantCaptureKeyboard {
          imgui.IO_AddInputCharacter(io, e.CharCode)
        }
      }
      case Platform.EventMouseSetCursor: {
        cursor := Platform.MouseCursor.ARROW;
        #partial switch imgui.GetMouseCursor() {
          case imgui.MouseCursor.Arrow:        Platform.SetMouseCursor(.ARROW)
          case imgui.MouseCursor.TextInput:    Platform.SetMouseCursor(.TEXT_INPUT)
          case imgui.MouseCursor.ResizeAll:    Platform.SetMouseCursor(.RESIZE_ALL)
          case imgui.MouseCursor.ResizeEW:     Platform.SetMouseCursor(.RESIZE_EW)
          case imgui.MouseCursor.ResizeNS:     Platform.SetMouseCursor(.RESIZE_NS)
          case imgui.MouseCursor.ResizeNESW:   Platform.SetMouseCursor(.RESIZE_NESW)
          case imgui.MouseCursor.ResizeNWSE:   Platform.SetMouseCursor(.RESIZE_NWSE)
          case imgui.MouseCursor.Hand:         Platform.SetMouseCursor(.HAND)
          case imgui.MouseCursor.NotAllowed:   Platform.SetMouseCursor(.NOT_ALLOWED)
        }
      }
    }
  }
}

ImGui_Begin :: proc(ctx: ^ImGuiBackend, dt: f32, width, height: f32) {
  imgui.SetCurrentContext(ctx.Context)
  io := imgui.GetIO()
  io.DisplaySize = { width, height }
  io.DeltaTime = dt
    
  imgui.NewFrame()
}

ImGui_End :: proc() {
  imgui.Render()
}

SliceFromViewports :: proc(v: imgui.Vector_ViewportPtr) -> []type_of(v.Data^) {
  return (([^]type_of(v.Data^))(v.Data))[0:v.Size]
}

SliceFromCmdLists :: proc(v: imgui.Vector_DrawListPtr) -> []type_of(v.Data^) {
  return (([^]type_of(v.Data^))(v.Data))[0:v.Size]
}

SliceFromIndices :: proc(v: imgui.Vector_DrawIdx) -> []type_of(v.Data^) {
  return (([^]type_of(v.Data^))(v.Data))[0:v.Size]
}

SliceFromVertices :: proc(v: imgui.Vector_DrawVert) -> []type_of(v.Data^) {
  return (([^]type_of(v.Data^))(v.Data))[0:v.Size]
}

SliceFromDrawCmds :: proc(v: imgui.Vector_DrawCmd) -> []type_of(v.Data^) {
  return (([^]type_of(v.Data^))(v.Data))[0:v.Size]
}

SliceFromImVector :: proc { SliceFromViewports, SliceFromCmdLists, SliceFromIndices, SliceFromVertices, SliceFromDrawCmds }


ImGui_Render :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  platformIo := imgui.GetPlatformIO()
  
  GpuPreparePipeline(gpu, gpuRes, Platform.GetWindowClientSize(window))
  
  for viewport in SliceFromImVector(platformIo.Viewports) {
    if .IsMinimized in viewport.Flags {
      continue
    }
    
    context.allocator = context.temp_allocator  
    vertices: [dynamic]VertexImGui
    indices : [dynamic]u16
    
    //Create one big vertex/index buffer for the whole viewport so we can upload to the GPU with just one call (per buffer)
    cmdLists := SliceFromImVector(viewport.DrawData_.CmdLists)[0:viewport.DrawData_.CmdListsCount]
    for cmdList in cmdLists {
      #assert(size_of(imgui.DrawVert) == size_of(VertexImGui))
      for v in SliceFromImVector(cmdList.VtxBuffer) {
        append(&vertices, transmute(VertexImGui)v)
      }
      
      #assert(size_of(i16) == size_of(imgui.Wchar))
      for index in SliceFromImVector(cmdList.IdxBuffer) {
        append(&indices, index)
      }
    }
    
    GpuUploadVertexBuffer(vertices[:], gpu, gpuRes)
    GpuUploadIndexBuffer (indices [:], gpu, gpuRes)
    GpuBindDrawBuffers(gpu, gpuRes, window)

    drawListIdxOffset: u32
    drawListVtxOffset: i32
    for cmdList in cmdLists {
      for &cmd in SliceFromImVector(cmdList.CmdBuffer) {
        GpuSetPixelClipRect(
          gpu,
          left   = i32(cmd.ClipRect.x - viewport.DrawData_.DisplayPos.x),
          top    = i32(cmd.ClipRect.y - viewport.DrawData_.DisplayPos.y),
          right  = i32(cmd.ClipRect.z - viewport.DrawData_.DisplayPos.x),
          bottom = i32(cmd.ClipRect.w - viewport.DrawData_.DisplayPos.y),
          windowHeight = i32(Platform.GetWindowClientSize(window).y),
        )
        
        GpuBindTexture(gpu, imgui.DrawCmd_GetTexID(&cmd))
        if cmd.UserCallback != nil { 
          cmd.UserCallback(cmdList, &cmd)
        }
        else {
          GpuDraw(cmd.ElemCount, drawListIdxOffset + cmd.IdxOffset, drawListVtxOffset + i32(cmd.VtxOffset), gpu, gpuRes, window)
        }
      }
      drawListIdxOffset += u32(cmdList.IdxBuffer.Size);
      drawListVtxOffset += i32(cmdList.VtxBuffer.Size);
    }
  }
}

ImGuiKeyFromPlatform :: proc(key: Platform.Key) -> imgui.Key {
  switch key {
    case .A: return .A
    case .B: return .B
    case .C: return .C
    case .D: return .D
    case .E: return .E
    case .F: return .F
    case .G: return .G
    case .H: return .H
    case .I: return .I
    case .J: return .J
    case .K: return .K
    case .L: return .L
    case .M: return .M
    case .N: return .N
    case .O: return .O
    case .P: return .P
    case .Q: return .Q
    case .R: return .R
    case .S: return .S
    case .T: return .T
    case .U: return .U
    case .V: return .V
    case .W: return .W
    case .X: return .X
    case .Y: return .Y
    case .Z: return .Z
    
    case .N0: return ._0
    case .N1: return ._1
    case .N2: return ._2
    case .N3: return ._3
    case .N4: return ._4
    case .N5: return ._5
    case .N6: return ._6
    case .N7: return ._7
    case .N8: return ._8
    case .N9: return ._9
    
    case .F1 : return .F1 
    case .F2 : return .F2 
    case .F3 : return .F3 
    case .F4 : return .F4 
    case .F5 : return .F5 
    case .F6 : return .F6 
    case .F7 : return .F7 
    case .F8 : return .F8 
    case .F9 : return .F9 
    case .F10: return .F10
    case .F11: return .F11
    case .F12: return .F12
    case .F13: return .F13
    case .F14: return .F14
    case .F15: return .F15
    case .F16: return .F16
    case .F17: return .F17
    case .F18: return .F18
    case .F19: return .F19
    case .F20: return .F20
    case .F21: return .F21
    case .F22: return .F22
    case .F23: return .F23
    case .F24: return .F24
    
    case .NUMPAD_0: return .Keypad0
    case .NUMPAD_1: return .Keypad1
    case .NUMPAD_2: return .Keypad2
    case .NUMPAD_3: return .Keypad3
    case .NUMPAD_4: return .Keypad4
    case .NUMPAD_5: return .Keypad5
    case .NUMPAD_6: return .Keypad6
    case .NUMPAD_7: return .Keypad7
    case .NUMPAD_8: return .Keypad8
    case .NUMPAD_9: return .Keypad9
    
    case .NUM_MULTIPLY: return .KeypadMultiply
    case .NUM_ADD     : return .KeypadAdd
    case .NUM_SUBTRACT: return .KeypadSubtract
    case .NUM_DECIMAL : return .KeypadDecimal
    case .NUM_DIVIDE  : return .KeypadDivide
    case .NUM_LOCK    : assert(false); return .None
    //case .NUM_ENTER   : return VK_
    
    case .ESCAPE: return .Escape
    case .PRINT : return .PrintScreen
    case .PAUSE : return .Pause
    case .SCROLL_LOCK: return .ScrollLock
    
    case .INSERT   : return .Insert
    case .DELETE   : return .Delete
    case .HOME     : return .Home
    case .END      : return .End
    case .PAGE_UP  : return .PageUp
    case .PAGE_DOWN: return .PageDown
    
    case .ARROW_LEFT : return .LeftArrow
    case .ARROW_RIGHT: return .RightArrow
    case .ARROW_UP   : return .UpArrow
    case .ARROW_DOWN : return .DownArrow
    
    case .SPACE    : return .Space
    case .ENTER    : return .Enter
    case .BACKSPACE: return .Backspace
    
    case .TAB: return .Tab
    case .CAPS_LOCK: return .CapsLock
    
    case .COMMA       : return .Comma
    case .PERIOD      : return .Period
    case .APOSTROPHE  : return .Apostrophe
    case .MINUS       : return .Minus
    case .SLASH       : return .Slash
    case .BACKSLASH   : return .Backslash
    case .SEMICOLON   : return .Semicolon
    case .EQUAL       : return .Equal
    case .BRACKET_L   : return .LeftBracket
    case .BRACKET_R   : return .RightBracket
    case .ACCENT_GRAVE: return .GraveAccent
    
    case .CTRL_L : return .LeftCtrl
    case .CTRL_R : return .RightCtrl
    case .SHIFT_L: return .LeftShift
    case .SHIFT_R: return .RightShift
    case .ALT_L  : return .LeftAlt
    case .ALT_R  : return .RightAlt
    case .WIN_L  : return .LeftSuper
    case .WIN_R  : return .RightSuper
    
    //Our Platform layer resolves modifiers to their respective left/right version.
    //The generic ones here are just used internally and not relevant for our imgui backend
    case ._CTRL : assert(false); return .None
    case ._SHIFT: assert(false); return .None
    case ._ALT  : assert(false); return .None
    
    case .NONE: return .None
  }
  return .None
}