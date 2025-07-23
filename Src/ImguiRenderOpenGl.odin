package main
import "core:slice"
import "core:mem"
import "core:log"

import gl "vendor:opengl"
import win32 "core:sys/windows"

import "Platform"

when RENDERER == "OPEN_GL" {

GpuVertexBuffer :: struct {
  Buffer: u32,
  LenBytes: int,
}

GpuIndexBuffer :: struct {
  Buffer: u32,
  LenBytes: int,
}

GpuShaderConstBuffer :: struct #align(16) {
  ViewportSize : [2]f32,
}

Gpu :: struct {
}

//GPU resources
GpuRes :: struct {
  ShaderUi: u32,
  
  FontTexture: u32,
  
  VBufferUi: GpuVertexBuffer,
  IBufferUi: GpuIndexBuffer,
  MeshUi: u32,
}

GpuInit :: proc(window: Platform.Window) -> (gpu: ^Gpu, gpuRes: ^GpuRes) {
  gpu    = new(Gpu   )
  gpuRes = new(GpuRes)
  
  gl.load_up_to(3, 3, proc(p: rawptr, name: cstring) { 
    (cast(^rawptr)p)^ = win32.wglGetProcAddress(name)
  })
  
  gl.load_1_0(proc(p: rawptr, name: cstring) { 
    win32.gl_set_proc_address(p, name)
  })
  
  vShader := gl.CreateShader(gl.VERTEX_SHADER  )
  fShader := gl.CreateShader(gl.FRAGMENT_SHADER)
  
  vSource := #load("../data/shaders/ImGuiV.glsl", cstring)
  fSource := #load("../data/shaders/ImGuiF.glsl", cstring)
  gl.ShaderSource(vShader, 1, &vSource, nil)
  gl.ShaderSource(fShader, 1, &fSource, nil)
  gl.CompileShader(vShader)
  gl.CompileShader(fShader)
  
  program := gl.CreateProgram()
  gl.AttachShader(program, vShader)
  gl.AttachShader(program, fShader)
  gl.LinkProgram(program)
  gpuRes.ShaderUi = program
  
  gl.DeleteShader(vShader)
  gl.DeleteShader(fShader)
         
  gl.GenBuffers(1, &gpuRes.VBufferUi.Buffer)
  gl.GenBuffers(1, &gpuRes.IBufferUi.Buffer)
  
  gl.GenVertexArrays(1, &gpuRes.MeshUi)
  gl.BindVertexArray(gpuRes.MeshUi)
  gl.BindBuffer(gl.ARRAY_BUFFER        , gpuRes.VBufferUi.Buffer)
  gl.EnableVertexAttribArray(0)
  gl.EnableVertexAttribArray(1)
  gl.EnableVertexAttribArray(2)
  gl.VertexAttribPointer (0, 2, gl.FLOAT, false , size_of([2]f32) * 2 + size_of(u32), 0)
  gl.VertexAttribPointer (1, 2, gl.FLOAT, false , size_of([2]f32) * 2 + size_of(u32), size_of([2]f32) * 1)
  gl.VertexAttribIPointer(2, 4, gl.UNSIGNED_BYTE, size_of([2]f32) * 2 + size_of(u32), size_of([2]f32) * 2)
  gl.BindBuffer(gl.ARRAY_BUFFER        , 0)
  gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gpuRes.IBufferUi.Buffer)
  gl.BindVertexArray(0)
  gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
            
  return gpu, gpuRes
}

GpuFree :: proc(gpu: ^Gpu, gpuRes: ^GpuRes) {
  //@TODO (alektron) Cleanup OpenGL resources

  free(gpu)
  free(gpuRes)
}

GpuResizeRenderTargetToWindow :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  //Default framebuffer gets resized automatically
}

GpuUploadBuffer :: proc(type: u32, gpuBuff: ^$B, data: []$V, gpu: ^Gpu, growFactor: i32 = 2) {
  gl.BindVertexArray(0)  
  gl.BindBuffer(type, gpuBuff.Buffer)
  
  //Resize if necessary
  if gpuBuff.LenBytes < len(data) * size_of(V) {
    gpuBuff.LenBytes = len(data) * size_of(V) * int(growFactor)
    
    gl.BufferData(type, gpuBuff.LenBytes, nil, gl.DYNAMIC_DRAW)
  }
  
  gl.BufferSubData(type, 0, len(data) * size_of(V), raw_data(data))  
  gl.BindBuffer(type, 0)
}

GpuUploadVertexBuffer :: proc(data: []$V,  gpu: ^Gpu, gpuRes: ^GpuRes, growFactor: i32 = 2) {
  GpuUploadBuffer(gl.ARRAY_BUFFER, &gpuRes.VBufferUi, data, gpu)
}

GpuUploadIndexBuffer :: proc(data: []$V,  gpu: ^Gpu, gpuRes: ^GpuRes, growFactor: i32 = 2) {
  GpuUploadBuffer(gl.ELEMENT_ARRAY_BUFFER, &gpuRes.IBufferUi, data, gpu)
}

GpuCreateAndUploadTexture :: proc(pixels: []u8, width, height, bytesPerPixel: u32, gpu: ^Gpu, gpuRes: ^GpuRes) -> u64 {
  gl.GenTextures(1, &gpuRes.FontTexture)
  gl.BindTexture(gl.TEXTURE_2D, gpuRes.FontTexture)
  
  gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(width), i32(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
  gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
  gl.BindTexture(gl.TEXTURE_2D, 0)

  return u64(gpuRes.FontTexture)
}

GpuPreparePipeline :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, windowSize: [2]f32) {
  col := [4]f32{ 0.3, 0.3, 0.3, 1 }
  gl.Disable(gl.CULL_FACE)
  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
  gl.Disable(gl.DEPTH_TEST)
  gl.Viewport(0, 0, i32(windowSize.x), i32(windowSize.y))
  gl.Enable(gl.SCISSOR_TEST)
  gl.Scissor(0, 0, i32(windowSize.x), i32(windowSize.y))
  gl.ClearColor(col.x, col.y, col.z, col.w)
  gl.Clear(gl.COLOR_BUFFER_BIT)
  
  gl.UseProgram(gpuRes.ShaderUi)
  loc := gl.GetUniformLocation(gpuRes.ShaderUi, "u_ViewportSize")
  gl.Uniform2f(loc, windowSize.x, windowSize.y)
}

GpuBindDrawBuffers :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  gl.BindVertexArray(gpuRes.MeshUi)  
}

GpuDraw :: proc(num, iOffset: u32, vOffset: i32, gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  gl.DrawElementsBaseVertex(gl.TRIANGLES, i32(num), gl.UNSIGNED_SHORT, transmute(rawptr)(u64(iOffset * size_of(u16))), vOffset)
}

UnpackFromPointer :: proc(unpack: rawptr, $T: typeid) -> T {
  unpack := unpack
  #assert(size_of(T) <= size_of(rawptr))
  result: T
  mem.copy(&result, &unpack, size_of(result))
  return result
}

GpuBindTexture :: proc(gpu: ^Gpu, id: rawptr) {
  gl.ActiveTexture(gl.TEXTURE0)
  gl.BindTexture(gl.TEXTURE_2D, UnpackFromPointer(id, u32))
}

GpuSetPixelClipRect :: proc(gpu: ^Gpu, left, right, top, bottom: i32, windowHeight: i32) {
  gl.Scissor(left, windowHeight - bottom, right - left, bottom - top)
}

GpuPresent :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  dc := win32.GetDC(window.Handle)
  win32.SwapBuffers(dc)
  win32.ReleaseDC(window.Handle, dc)
}

}