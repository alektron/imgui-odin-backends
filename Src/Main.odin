package main 

import "base:runtime"
import "core:c"
import "core:strings"
import "core:mem/virtual"
import "core:mem"
import "core:math"
import "core:slice"
import "core:log"
import "core:fmt"

//Currently needed for presenting with software renderer
import win32 "core:sys/windows"

import "../Libraries/imgui"

import "Platform"

RENDERER :: #config(RENDERER, "SW")

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
	
	Platform.InputInit()
	Platform.WindowInit()
	window := Platform.CreateAndShowWindow("ImGui Demo")
	if !Platform.WindowIsValid(window) {
	  log.error("Could not create window")
	  return
	}
  
  gpu, gpuRes := GpuInit(window)
  
  imguiBackend: ImGuiBackend
  ImGui_Init(&imguiBackend, #load("../data/fonts/Comfortaa-Medium.ttf"), gpu, gpuRes)
  
  Time :: struct {
    Total: f64,
    Delta: f64,
  }

  time: Time
  time.Delta = 0.016 //Initialize to a non-zero value for the first frame
  shouldExit := false

  for !shouldExit {
    frameTimer: Platform.Timer
    Platform.TimerStart(&frameTimer)
    
    //At the beginning of every frame we have to clear the temp allocator.
    free_all(context.temp_allocator)
    
    events := Platform.GetEvents(window)
    for ev in events {
      if e, ok := ev.(Platform.EventClose); ok {
        shouldExit = true
      }
    } 
    ImGui_Events(events)
    
    windowSize := Platform.GetWindowClientSize(window)
    ImGui_Begin(&imguiBackend, f32(time.Delta), f32(windowSize.x),  f32(windowSize.y))
    
    //imgui.DockSpaceOverViewport()
    imgui.ShowDemoWindow()
    
    ImGui_End()
    
    //When the window gets continuously resized for a longer period of time, resize events accumulate.
    //It doesn't make much sense to react to all of them since the thread is stalling during the resize anyways.
    //By doing a reverse loop and breaking at the first resize event we only react to the last one.
    #reverse for eBase in events {
      if e, ok := eBase.(Platform.EventResize); ok && e.Size.x > 0 && e.Size.y > 0 {
        GpuResizeRenderTargetToWindow(gpu, gpuRes, window)
        break;
      }
    }

    ImGui_Render(gpu, gpuRes, window)

    if !Platform.WindowIsMinimized(window) {
      when RENDERER == "D3D" {
        gpu.Swapchain->Present(1, { })
      }
      else {
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
    else {
      Platform.ThreadSleep(30)
    }
    
    time.Delta = f64(Platform.TimerGetMicroseconds(&frameTimer)) / 1000000
    time.Total += time.Delta
  }    
  
  ImGui_Free(&imguiBackend)
  GpuFree(gpu, gpuRes)
}