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
  
  ColorVecFromU32 :: proc(col: u32) -> [4]f32 {
    return {
      f32((col >>  0) & 0xFF) / 255,
      f32((col >>  8) & 0xFF) / 255,
      f32((col >> 16) & 0xFF) / 255,
      f32((col >> 24) & 0xFF) / 255,
    }
  }
  
  DrawTriangle :: proc(aV, bV, cV: VertexImGui, tex: Texture, target: Texture, clipMin, clipMax: [2]i32) {
    //@TODO (alektron) Sub pixel precision and fill rules.
    aPos := linalg.to_i32(aV.Pos)
    bPos := linalg.to_i32(bV.Pos)
    cPos := linalg.to_i32(cV.Pos)
    
    //Calculate triangle bounds and clip to clipping rectangle
    min := linalg.min(aPos, bPos, cPos)
    max := linalg.max(aPos, bPos, cPos)
    
    //Clip to clip rectangle
    //We expect the caller to always a clip rectangle to clip at least to the max target size.
    //This way we save us another explicit min/max call here.
    min = linalg.max(min, clipMin)
    max = linalg.min(max, clipMax - { 1, 1 })
    
    area := SignedTriangleArea(aPos, bPos, cPos)
    for x in min.x..=max.x {
      for y in min.y..=max.y {
        //Barycentric coordinates
        alpha := SignedTriangleArea({ x, y }, bPos, cPos) / area
        beta  := SignedTriangleArea({ x, y }, cPos, aPos) / area
        gamma := SignedTriangleArea({ x, y }, aPos, bPos) / area
        
        if !(alpha < 0 || beta < 0 || gamma < 0) {
          vCol: [4]f32 = alpha * ColorVecFromU32(aV.Col) + beta * ColorVecFromU32(bV.Col) + gamma * ColorVecFromU32(cV.Col)
          
          uvRel := alpha * aV.Tex + beta * bV.Tex + gamma * cV.Tex
          uvAbs := linalg.to_i32(linalg.to_f32(tex.Size - 1) * uvRel)
          
          texelIndex := tex.BytePerPixel * (tex.Size.x * uvAbs.y + uvAbs.x)
          tCol: [4]f32 = {
            f32(tex.Data[texelIndex + 0]) / 255,
            f32(tex.Data[texelIndex + 1]) / 255,
            f32(tex.Data[texelIndex + 2]) / 255,
            f32(tex.Data[texelIndex + 3]) / 255,
          }
          
          pixels := TextureDataAsPixel(target)
          
          pixelIndex := x + (target.Size.y - y - 1) * target.Size.x
          outCol := vCol * tCol
          inCol  := linalg.to_f32(pixels[pixelIndex]).bgra / 255

          //Alpha blending
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

GpuSetPixelClipRect :: proc(gpu: ^Gpu, left, right, top, bottom: i32, windowHeight: i32) {
  gpu.ClipMin.x = left
  gpu.ClipMin.y = top
  gpu.ClipMax.x = right
  gpu.ClipMax.y = bottom
}

GpuPresent :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  windowSize := Platform.GetWindowClientSize(window)
  
  //@TODO (alektron) This is NOT how to properly redraw at a fixed framerate.
  //Software renderer is experimental, this is just for testing.
  bitmapInfo: win32.BITMAPINFO
  bitmapInfo.bmiHeader.biSize = size_of(bitmapInfo.bmiHeader)
  bitmapInfo.bmiHeader.biWidth  = i32(windowSize.x)
  bitmapInfo.bmiHeader.biHeight = i32(windowSize.y)
  bitmapInfo.bmiHeader.biPlanes = 1
  bitmapInfo.bmiHeader.biBitCount = 32
  bitmapInfo.bmiHeader.biCompression = win32.BI_RGB
  
  hdc := win32.GetDC(window.Handle)
  win32.StretchDIBits(
    hdc,
    0, 0, i32(windowSize.x), i32(windowSize.y),
    0, 0, i32(windowSize.x), i32(windowSize.y),
    raw_data(gpuRes.RenderTarget.Data),
    &bitmapInfo,
    win32.DIB_RGB_COLORS,
    win32.SRCCOPY
  )
  
  win32.ReleaseDC(window.Handle, hdc)
}

}