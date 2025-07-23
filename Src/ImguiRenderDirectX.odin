package main
import "core:slice"
import "core:mem"
import "core:log"

import "vendor:directx/dxgi"
import d3d "vendor:directx/d3d11"
import "vendor:directx/d3d_compiler"

import "Platform"

when RENDERER == "D3D" {

GpuVertexBuffer :: struct {
  Buffer: ^d3d.IBuffer,
  LenBytes: int,
}

GpuIndexBuffer :: struct {
  Buffer: ^d3d.IBuffer,
  LenBytes: int,
}

GpuShaderConstBuffer :: struct #align(16) {
  ViewportSize : [2]f32,
}

Gpu :: struct {
  Swapchain     : ^dxgi.ISwapChain,
  Device        : ^d3d.IDevice,
  DeviceContext : ^d3d.IDeviceContext,
}

//GPU resources
GpuRes :: struct {
  //Backbuffer render targets
  RenderTarget: ^d3d.ITexture2D,
  RenderTargetView: ^d3d.IRenderTargetView,
  
  //Render state (rasterizer, blend state etc.)
  Rasterizer2d: ^d3d.IRasterizerState,
  SamplerState: ^d3d.ISamplerState,
  BlendState: ^d3d.IBlendState,
  
  FontTexture: ^d3d.ITexture2D,
  FontTextureView: ^d3d.IShaderResourceView,
    
  ConstBuffer: ^d3d.IBuffer,
  
  VsUi: ^d3d.IVertexShader,
  PsUi: ^d3d.IPixelShader,
  LayoutUi: ^d3d.IInputLayout,
  
  VBufferUi: GpuVertexBuffer,
  IBufferUi: GpuIndexBuffer,
}

GpuInit :: proc(window: Platform.Window) -> (gpu: ^Gpu, gpuRes: ^GpuRes) {
  gpu    = new(Gpu   )
  gpuRes = new(GpuRes)

  {
    windowSize := Platform.GetWindowClientSize(window)
  
    swapchaindesc : dxgi.SWAP_CHAIN_DESC
    swapchaindesc.BufferDesc.Width  = u32(windowSize.x)
    swapchaindesc.BufferDesc.Height = u32(windowSize.y)
    swapchaindesc.BufferDesc.Format = dxgi.FORMAT.B8G8R8A8_UNORM
    swapchaindesc.SampleDesc.Count  = 1
    swapchaindesc.BufferUsage       = { .RENDER_TARGET_OUTPUT }
    swapchaindesc.BufferCount       = 2
    swapchaindesc.OutputWindow      = window.Handle
    swapchaindesc.Windowed          = true
    swapchaindesc.SwapEffect        = dxgi.SWAP_EFFECT.FLIP_DISCARD
  
    when ODIN_DEBUG {
        d3d.CreateDeviceAndSwapChain(nil, d3d.DRIVER_TYPE.HARDWARE, nil, { .DEBUG }, nil, 0, 7, &swapchaindesc, &gpu.Swapchain, &gpu.Device, nil, &gpu.DeviceContext);
    }
    else {
        d3d.CreateDeviceAndSwapChain(nil, d3d.DRIVER_TYPE.HARDWARE, nil, { }, nil, 0, 7, &swapchaindesc, &gpu.Swapchain, &gpu.Device, nil, &gpu.DeviceContext);
    }
    gpu.Swapchain->GetDesc(&swapchaindesc);
  }

  gpu.Swapchain->GetBuffer(0, d3d.ITexture2D_UUID, (^rawptr)(&gpuRes.RenderTarget))
  gpu.Device->CreateRenderTargetView(gpuRes.RenderTarget, nil, &gpuRes.RenderTargetView)
      
  {
    samplerdesc : d3d.SAMPLER_DESC
    samplerdesc.Filter         = d3d.FILTER.MIN_MAG_MIP_POINT
    samplerdesc.AddressU       = d3d.TEXTURE_ADDRESS_MODE.CLAMP
    samplerdesc.AddressV       = d3d.TEXTURE_ADDRESS_MODE.CLAMP
    samplerdesc.AddressW       = d3d.TEXTURE_ADDRESS_MODE.CLAMP
    samplerdesc.ComparisonFunc = d3d.COMPARISON_FUNC.NEVER
  
    gpu.Device->CreateSamplerState(&samplerdesc, &gpuRes.SamplerState);
  }
  
  CreateShaderAndInputLayout :: proc(gpu: ^Gpu, source: string, layout: ^^d3d.IInputLayout, desc: []d3d.INPUT_ELEMENT_DESC, vShader: ^^d3d.IVertexShader, pShader: ^^d3d.IPixelShader) {
    shaderCompilationOutput : ^d3d.IBlob
    errorBlob : ^d3d.IBlob
    if d3d_compiler.Compile(raw_data(source), len(source), nil, nil, nil, "vertex_shader", "vs_5_0", 0, 0, &shaderCompilationOutput, &errorBlob) != 0 {
      log.error(cstring(errorBlob->GetBufferPointer()))
      errorBlob->Release()
    }
    gpu.Device->CreateVertexShader(shaderCompilationOutput->GetBufferPointer(), shaderCompilationOutput->GetBufferSize(), nil, vShader);

    gpu.Device->CreateInputLayout(raw_data(desc), u32(len(desc)), shaderCompilationOutput->GetBufferPointer(), shaderCompilationOutput->GetBufferSize(), layout);
    shaderCompilationOutput->Release()
  
    d3d_compiler.Compile(raw_data(source), len(source), nil, nil, nil, "pixel_shader", "ps_5_0", 0, 0, &shaderCompilationOutput, nil)
    gpu.Device->CreatePixelShader(shaderCompilationOutput->GetBufferPointer(), shaderCompilationOutput->GetBufferSize(), nil, pShader);
    shaderCompilationOutput->Release()  
  }
  
  IMGUI_LAYOUT_DESC := [?]d3d.INPUT_ELEMENT_DESC {
    { "POS", 0, dxgi.FORMAT.R32G32_FLOAT, 0, 0, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    { "TEX", 0, dxgi.FORMAT.R32G32_FLOAT   , 0, d3d.APPEND_ALIGNED_ELEMENT, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    { "COL", 0, dxgi.FORMAT.R32_UINT, 0, d3d.APPEND_ALIGNED_ELEMENT, d3d.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
  }

  CreateShaderAndInputLayout(gpu, #load("../data/shaders/ImGui.hlsl", string), &gpuRes.LayoutUi, IMGUI_LAYOUT_DESC[:], &gpuRes.VsUi, &gpuRes.PsUi)
      
  CreateConstantBuffer :: proc($T: typeid, gpu: ^Gpu) -> ^d3d.IBuffer {
    bufferdesc : d3d.BUFFER_DESC;
    bufferdesc.ByteWidth      = size_of(T);
    bufferdesc.Usage          = d3d.USAGE.DYNAMIC;
    bufferdesc.BindFlags      = { .CONSTANT_BUFFER };
    bufferdesc.CPUAccessFlags = { .WRITE };
    
    result: ^d3d.IBuffer
    gpu.Device->CreateBuffer(&bufferdesc, nil, &result);
    return result
  }
  
  gpuRes.ConstBuffer = CreateConstantBuffer(GpuShaderConstBuffer, gpu)
  
  {
    rasterizerdesc : d3d.RASTERIZER_DESC 
    rasterizerdesc.FillMode = d3d.FILL_MODE.SOLID
    rasterizerdesc.CullMode = d3d.CULL_MODE.NONE
    rasterizerdesc.ScissorEnable = true

    gpu.Device->CreateRasterizerState(&rasterizerdesc, &gpuRes.Rasterizer2d);
  }
  
  {
    blendDesc : d3d.BLEND_DESC
    blendDesc.RenderTarget[0].BlendEnable = true
    blendDesc.RenderTarget[0].RenderTargetWriteMask = 255;
    blendDesc.RenderTarget[0].SrcBlend = d3d.BLEND.SRC_ALPHA;
    blendDesc.RenderTarget[0].DestBlend = d3d.BLEND.INV_SRC_ALPHA;
    blendDesc.RenderTarget[0].BlendOp = d3d.BLEND_OP.ADD;
    blendDesc.RenderTarget[0].SrcBlendAlpha = d3d.BLEND.SRC_ALPHA;
    blendDesc.RenderTarget[0].DestBlendAlpha = d3d.BLEND.DEST_ALPHA;
    blendDesc.RenderTarget[0].BlendOpAlpha = d3d.BLEND_OP.ADD;
    blendDesc.RenderTarget[0].RenderTargetWriteMask = u8(d3d.COLOR_WRITE_ENABLE_ALL);
    gpu.Device->CreateBlendState(&blendDesc, &gpuRes.BlendState)
  }
        
  {
    bufferdesc : d3d.BUFFER_DESC
    bufferdesc.ByteWidth = size_of(VertexImGui) * 100
    bufferdesc.CPUAccessFlags = { .WRITE }
    bufferdesc.Usage     = d3d.USAGE.DYNAMIC
    bufferdesc.BindFlags = { .VERTEX_BUFFER }

    gpu.Device->CreateBuffer(&bufferdesc, nil, &gpuRes.VBufferUi.Buffer)
  }
  
  {
    bufferdesc : d3d.BUFFER_DESC
    bufferdesc.ByteWidth = size_of(u32) * 100
    bufferdesc.CPUAccessFlags = { .WRITE }
    bufferdesc.Usage     = d3d.USAGE.DYNAMIC
    bufferdesc.BindFlags = { .INDEX_BUFFER }

    gpu.Device->CreateBuffer(&bufferdesc, nil, &gpuRes.IBufferUi.Buffer)
  }
  
  return gpu, gpuRes
}

GpuFree :: proc(gpu: ^Gpu, gpuRes: ^GpuRes) {
  gpuRes.RenderTarget->Release()
  gpuRes.RenderTargetView->Release()
  
  gpuRes.Rasterizer2d->Release()
  gpuRes.SamplerState->Release()
  gpuRes.BlendState->Release()
  
  gpuRes.FontTexture->Release()
  gpuRes.FontTextureView->Release()
  
  gpuRes.ConstBuffer->Release()
  
  gpuRes.VsUi->Release()
  gpuRes.PsUi->Release()
  gpuRes.LayoutUi->Release()
  
  gpuRes.VBufferUi.Buffer->Release()
  gpuRes.IBufferUi.Buffer->Release()
  
  gpu.Swapchain->Release()
  gpu.Device->Release()
  gpu.DeviceContext->Release()

  free(gpu)
  free(gpuRes)
}

GpuResizeRenderTargetToWindow :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  gpuRes.RenderTargetView->Release()
  gpuRes.RenderTarget->Release()
  gpu.Swapchain->ResizeBuffers(0, 0, 0, .UNKNOWN, {})       

  gpu.Swapchain->GetBuffer(0, d3d.ITexture2D_UUID, (^rawptr)(&gpuRes.RenderTarget))
  gpu.Device->CreateRenderTargetView(gpuRes.RenderTarget, nil, &gpuRes.RenderTargetView)   
}

GpuUploadBuffer :: proc(gpuBuff: ^$B, data: []$V, gpu: ^Gpu, growFactor: i32 = 2) {
  //Resize if necessary
  if gpuBuff.LenBytes < len(data) * size_of(V) {
    gpuBuff.LenBytes = len(data) * size_of(V) * int(growFactor)
    
    desc: d3d.BUFFER_DESC
    gpuBuff.Buffer->GetDesc(&desc)
    desc.ByteWidth = u32(gpuBuff.LenBytes)

    gpuBuff.Buffer->Release()
    gpu.Device->CreateBuffer(&desc, nil, &gpuBuff.Buffer)
  }
  
  mapped: d3d.MAPPED_SUBRESOURCE
  gpu.DeviceContext->Map(gpuBuff.Buffer, 0, .WRITE_DISCARD, {}, &mapped)
  gpuData := slice.from_ptr((^V)(mapped.pData), gpuBuff.LenBytes / size_of(V))
  copy_slice(gpuData, data)
  gpu.DeviceContext->Unmap(gpuBuff.Buffer, 0)
}

GpuUploadVertexBuffer :: proc(data: []$V,  gpu: ^Gpu, gpuRes: ^GpuRes, growFactor: i32 = 2) {
  GpuUploadBuffer(&gpuRes.VBufferUi, data, gpu)
}

GpuUploadIndexBuffer :: proc(data: []$V,  gpu: ^Gpu, gpuRes: ^GpuRes, growFactor: i32 = 2) {
  GpuUploadBuffer(&gpuRes.IBufferUi, data, gpu)
}

GpuCreateAndUploadTexture :: proc(pixels: []u8, width, height, bytesPerPixel: u32, gpu: ^Gpu, gpuRes: ^GpuRes) -> u64 {
  texturedesc : d3d.TEXTURE2D_DESC
  texturedesc.Width  = width
  texturedesc.Height = height
  texturedesc.MipLevels = 1
  texturedesc.ArraySize = 1
  texturedesc.Format = dxgi.FORMAT.R8G8B8A8_UNORM
  texturedesc.SampleDesc.Count = 1
  texturedesc.Usage = d3d.USAGE.IMMUTABLE
  texturedesc.BindFlags = { .SHADER_RESOURCE }

  textureData : d3d.SUBRESOURCE_DATA
  textureData.pSysMem = raw_data(pixels)
  textureData.SysMemPitch = width * bytesPerPixel
  
  gpu.Device->CreateTexture2D(&texturedesc, &textureData, &gpuRes.FontTexture)
  gpu.Device->CreateShaderResourceView(gpuRes.FontTexture, nil, &gpuRes.FontTextureView)
  
  return transmute(u64)gpuRes.FontTextureView
}

GpuPreparePipeline :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, windowSize: [2]f32) {
  blendFactor := [?]f32{ 1, 1, 1, 1 }
  sampleMask : u32 = 0xffffffff
  gpu.DeviceContext->OMSetBlendState(gpuRes.BlendState, &blendFactor, sampleMask)
  
  {
    constantbufferMapped : d3d.MAPPED_SUBRESOURCE
    gpu.DeviceContext->Map(gpuRes.ConstBuffer, 0, d3d.MAP.WRITE_DISCARD, { }, &constantbufferMapped)
    buff := (^GpuShaderConstBuffer)(constantbufferMapped.pData)
    buff.ViewportSize = windowSize
    gpu.DeviceContext->Unmap(gpuRes.ConstBuffer, 0)
  }
  
  buffers := [?]^d3d.IBuffer{ gpuRes.ConstBuffer }
  gpu.DeviceContext->VSSetConstantBuffers(0, 1, raw_data(&buffers))
  gpu.DeviceContext->PSSetConstantBuffers(0, 1, raw_data(&buffers))

  gpu.DeviceContext->VSSetShader(gpuRes.VsUi, nil, 0)
  gpu.DeviceContext->PSSetShader(gpuRes.PsUi, nil, 0)
  gpu.DeviceContext->PSSetSamplers(0, 1, &gpuRes.SamplerState)
  gpu.DeviceContext->IASetInputLayout(gpuRes.LayoutUi)
  gpu.DeviceContext->RSSetState(gpuRes.Rasterizer2d)
  gpu.DeviceContext->IASetPrimitiveTopology(d3d.PRIMITIVE_TOPOLOGY.TRIANGLELIST)
  
  gpu.DeviceContext->OMSetRenderTargets(1, &gpuRes.RenderTargetView, nil)
  viewport := d3d.VIEWPORT{ 0, 0, f32(windowSize.x), f32(windowSize.y),  0, 1 };
  gpu.DeviceContext->RSSetViewports(1, &viewport);
  
  col := [4]f32{ 0.3, 0.3, 0.3, 1 }
  gpu.DeviceContext->ClearRenderTargetView(gpuRes.RenderTargetView, &col)
}

GpuBindDrawBuffers :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  stride : u32 = size_of(VertexImGui)
  offset : u32 = 0
  gpu.DeviceContext->IASetVertexBuffers(0, 1, &gpuRes.VBufferUi.Buffer, &stride, &offset)
  gpu.DeviceContext->IASetIndexBuffer(gpuRes.IBufferUi.Buffer, .R16_UINT, 0)
}

GpuDraw :: proc(num, iOffset: u32, vOffset: i32, gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  gpu.DeviceContext->DrawIndexed(num, iOffset, vOffset)
}

UnpackFromPointer :: proc(unpack: rawptr, $T: typeid) -> T {
  unpack := unpack
  #assert(size_of(T) <= size_of(rawptr))
  result: T
  mem.copy(&result, &unpack, size_of(result))
  return result
}

GpuBindTexture :: proc(gpu: ^Gpu, id: rawptr) {
  texHandle := UnpackFromPointer(id, ^d3d.IShaderResourceView)
  gpu.DeviceContext->PSSetShaderResources(0, 1, &texHandle)
}

GpuSetPixelClipRect :: proc(gpu: ^Gpu, left, right, top, bottom: i32, windowHeight: i32) {
  clipRect: d3d.RECT
  clipRect.left   = left
  clipRect.top    = top
  clipRect.right  = right
  clipRect.bottom = bottom
  gpu.DeviceContext->RSSetScissorRects(1, &clipRect)
}

GpuPresent :: proc(gpu: ^Gpu, gpuRes: ^GpuRes, window: Platform.Window) {
  gpu.Swapchain->Present(1, { })
}

}