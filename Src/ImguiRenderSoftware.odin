package main
import "core:slice"
import "core:mem"
import "core:log"
import "core:math"
import "core:math/linalg"

import win32 "core:sys/windows"

import "Platform"

when RENDERER == "SW" {
//NOTE: The software renderer is very much experimental.
//It runs okayish in optimized builds for regular sized demo window but it's not optimized AT ALL.
//If you resize to window to e.g. fit the screen, framrate drops substantially.
//There's also some minor visual glitches

Pixel :: [4]u8

Texture :: struct {
  Data: []u8,
  Size: [2]i32,
  BytePerPixel: i32,
}

TextureDataAsPixel :: proc(tex: Texture) -> []Pixel {
  return slice.from_ptr(([^]Pixel)(raw_data(tex.Data)), len(tex.Data) / int(tex.BytePerPixel))
}

Gpu :: struct {
  ClipMin: [2]i32,
  ClipMax: [2]i32,
}

//GPU resources
GpuRes :: struct {
  Vertices: [dynamic]VertexImGui,
  Indices : [dynamic]u16,
  
  RenderTarget: Texture,
  FontTex: Texture,
}


GpuInit :: proc(window: Platform.Window) -> (gpu: ^Gpu, gpuRes: ^GpuRes) {
  gpu    = new(Gpu   )
  gpuRes = new(GpuRes)
  
  ResizeDibSection(gpuRes, window)
  return gpu, gpuRes
}

GpuFree :: proc(gpu: ^Gpu, gpuRes: ^GpuRes) {
  free(gpu)
  free(gpuRes)
}

ResizeDibSection :: proc(gpuRes: ^GpuRes, window: Platform.Window) {
  if len(gpuRes.RenderTarget.Data) != 0 {
    win32.DeleteObject(win32.HGDIOBJ(raw_data(gpuRes.RenderTarget.Data)))
  }

  hdc := win32.GetDC(window.Handle)
  windowSize := Platform.GetWindowClientSize(window)
  
  bitmapInfo: win32.BITMAPINFO
  bitmapInfo.bmiHeader.biSize = size_of(bitmapInfo.bmiHeader)
  bitmapInfo.bmiHeader.biWidth  = i32(windowSize.x)
  bitmapInfo.bmiHeader.biHeight = i32(windowSize.y)
  bitmapInfo.bmiHeader.biPlanes = 1
  bitmapInfo.bmiHeader.biBitCount = 32
  bitmapInfo.bmiHeader.biCompression = win32.BI_RGB
  
  bitmapMem: rawptr
  win32.CreateDIBSection(hdc, &bitmapInfo, win32.DIB_RGB_COLORS, &bitmapMem, nil, 0)
  
  #assert(size_of(Pixel) == 4)
  gpuRes.RenderTarget.Data = slice.from_ptr(([^]u8)(bitmapMem), int(windowSize.x) * int(windowSize.y) * 4)
  gpuRes.RenderTarget.Size = { i32(windowSize.x), i32(windowSize.y)}
  gpuRes.RenderTarget.BytePerPixel = 4
  win32.ReleaseDC(window.Handle, hdc)
}

GpuResizeRenderTargetToWindow :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  ResizeDibSection(gpuRes, window)
}

GpuUploadVertexBuffer :: proc(data: []$V,  gpu: ^Gpu, gpuRes: ^GpuRes, growFactor: i32 = 2) {
  context.allocator = context.temp_allocator
  gpuRes.Vertices = {}
  for v in data do append(&gpuRes.Vertices, v)
}

GpuUploadIndexBuffer :: proc(data: []$V,  gpu: ^Gpu, gpuRes: ^GpuRes, growFactor: i32 = 2) {
  context.allocator = context.temp_allocator
  gpuRes.Indices = {}
  for v in data do append(&gpuRes.Indices, v)
}

GpuCreateAndUploadTexture :: proc(pixels: []u8, width, height, bytesPerPixel: u32, gpu: ^Gpu, gpuRes: ^GpuRes) -> u64 {
  gpuRes.FontTex.Size = { i32(width), i32(height) }
  gpuRes.FontTex.BytePerPixel = i32(bytesPerPixel)
  gpuRes.FontTex.Data, _ = slice.clone(pixels)
  return 0
}

GpuPreparePipeline :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, windowSize: [2]f32) {
  assert(gpuRes.RenderTarget.BytePerPixel == 4)
  col: f32 = 0.3
  
  slice.fill(TextureDataAsPixel(gpuRes.RenderTarget), Pixel{ u8(col * 255), u8(col * 255), u8(col * 255), 255 })
  
  gpu.ClipMin = {}
  gpu.ClipMax = { i32(windowSize.x), i32(windowSize.y) }
}

GpuBindDrawBuffers :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {

}

GpuDraw :: proc(num, iOffset: u32, vOffset: i32, gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  hdc := win32.GetDC(window.Handle)
  
  SignedTriangleArea :: proc(a, b, c: [2]i32) -> f32 {
    return 0.5 * f32((b.y - a.y) * (b.x + a.x) + (c.y - b.y) * (c.x + b.x) + (a.y - c.y) * (a.x + c.x))
  }
  
  ColorVecFromU32 :: proc(col: u32) -> Pixel {
    return {
      u8((col >>  0) & 0xFF),
      u8((col >>  8) & 0xFF),
      u8((col >> 16) & 0xFF),
      u8((col >> 24) & 0xFF),
    }
  }
  
  DrawTriangle :: proc(aV, bV, cV: VertexImGui, tex: Texture, target: Texture, clipMin, clipMax: [2]i32) {
    aPos := linalg.to_i32(aV.Pos)
    bPos := linalg.to_i32(bV.Pos)
    cPos := linalg.to_i32(cV.Pos)
    min := linalg.min(linalg.min(aPos, bPos), cPos)
    max := linalg.max(linalg.max(aPos, bPos), cPos)
    
    min = linalg.max(min, [2]i32{ 0, 0 })
    max = linalg.min(max, target.Size)
    
    min = linalg.max(min, clipMin)
    max = linalg.min(max, clipMax - { 1, 1 })
    
    area := SignedTriangleArea(aPos, bPos, cPos)
    
    for x in min.x..=max.x {
      for y in min.y..=max.y {
        alpha := SignedTriangleArea({ x, y }, bPos, cPos) / area
        beta  := SignedTriangleArea({ x, y }, cPos, aPos) / area
        gamma := SignedTriangleArea({ x, y }, aPos, bPos) / area
        
        if alpha >= 0 && beta >= 0 && gamma >= 0 {
          colA := ColorVecFromU32(aV.Col)
          colB := ColorVecFromU32(bV.Col)
          colC := ColorVecFromU32(cV.Col)
          
          vCol: [4]f32
          vCol.r = alpha * (f32(colA.r) / 255) + beta * (f32(colB.r) / 255) + gamma * (f32(colC.r) / 255)
          vCol.g = alpha * (f32(colA.g) / 255) + beta * (f32(colB.g) / 255) + gamma * (f32(colC.g) / 255)
          vCol.b = alpha * (f32(colA.b) / 255) + beta * (f32(colB.b) / 255) + gamma * (f32(colC.b) / 255)
          vCol.a = alpha * (f32(colA.a) / 255) + beta * (f32(colB.a) / 255) + gamma * (f32(colC.a) / 255)
          
          u := alpha * aV.Tex.x + beta * bV.Tex.x + gamma * cV.Tex.x
          v := alpha * aV.Tex.y + beta * bV.Tex.y + gamma * cV.Tex.y
          
          uAbs := i32(f32(tex.Size.x - 1) * u)
          vAbs := i32(f32(tex.Size.y - 1) * v)
          
          tCol: [4]f32
          tCol.r = f32(tex.Data[tex.BytePerPixel * (tex.Size.x * vAbs + uAbs) + 0]) / 255
          tCol.g = f32(tex.Data[tex.BytePerPixel * (tex.Size.x * vAbs + uAbs) + 1]) / 255
          tCol.b = f32(tex.Data[tex.BytePerPixel * (tex.Size.x * vAbs + uAbs) + 2]) / 255
          tCol.a = f32(tex.Data[tex.BytePerPixel * (tex.Size.x * vAbs + uAbs) + 3]) / 255
          
          pixels := TextureDataAsPixel(target)
          
          pixelIndex := x + (target.Size.y - y - 1) * target.Size.x
          outCol := vCol * tCol
          inCol  := linalg.to_f32(pixels[pixelIndex]).bgra / 255

          col: [4]u8 = linalg.to_u8((outCol * outCol.a + inCol * (1 - outCol.a)) * 255)
          pixels[pixelIndex] = { col.b, col.g, col.r, 255 }
        }
      }
    }
  }
  
  assert(num % 3 == 0)
  for index_i in 0..< num / 3 {
    a := gpuRes.Vertices[i32(gpuRes.Indices[(index_i * 3 + 0) + iOffset]) + (vOffset)]
    b := gpuRes.Vertices[i32(gpuRes.Indices[(index_i * 3 + 1) + iOffset]) + (vOffset)]
    c := gpuRes.Vertices[i32(gpuRes.Indices[(index_i * 3 + 2) + iOffset]) + (vOffset)]

    DrawTriangle(a, b, c, gpuRes.FontTex, gpuRes.RenderTarget, gpu.ClipMin, gpu.ClipMax)
  }
}

UnpackFromPointer :: proc(unpack: rawptr, $T: typeid) -> T {
  unpack := unpack
  #assert(size_of(T) <= size_of(rawptr))
  result: T
  mem.copy(&result, &unpack, size_of(result))
  return result
}

GpuBindTexture :: proc(gpu: ^Gpu, id: rawptr) {
  //@TODO (alektron) Support textures other than just the font texture
  //texHandle := UnpackFromPointer(id, ^d3d.IShaderResourceView)
}

GpuSetPixelClipRect :: proc(gpu: ^Gpu, left, right, top, bottom: i32) {
  gpu.ClipMin.x = left
  gpu.ClipMin.y = top
  gpu.ClipMax.x = right
  gpu.ClipMax.y = bottom
}

}