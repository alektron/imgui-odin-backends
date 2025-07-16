## Custom Dear ImGui backend for Odin

This is a custom platform and render backend for [Dear ImGui](https://github.com/ocornut/imgui) written in [Odin](https://odin-lang.org/). It serves the same purpose as the existing [backends](https://github.com/ocornut/imgui/tree/master/examples) that come with the official library.

## Motivation
The official backends support most relevant platforms and graphics APIs. They also cover much more edge cases and features than this implementation currently does. 
The Dear ImGui [Odin bindings](https://gitlab.com/L-4/odin-imgui) that are being used here, already support some of the official backends. However since they are written in C++, just like Dear ImGui itself, they are only available in Odin as precompiled binaries.

Having a native backend available in the language that your appliation is written in however, may also have its advantages. The most obvious ones being the ability to easily modify and debug.

It is written with simplicity in mind, so even if not used directly, it can serve as a starting point to implement your own backends.

## Features
Currently only Windows is supported as a platform with DirectX for rendering. The ImGui backend logic itself is neatly separated from platform and renderer with a thin abstraction layer and consists of only roughly ~250 LOC (minus some boilerplate to translate keyboard keys).

Implementing e.g. an OpenGL backend should be fairly trivial. As for the platform layer, I only have experience with Windows, so I can't tell how robust the abstraction is for other platforms. But it is simple enough that it should be very easily adjustable.

Except for some minor preparations, we do not currently support ImGui's multi-viewports. I have written backends before, that do support it but covering all edge cases is difficult so to keep it simple I have not yet done it here.

Speaking of edge cases, this is not a 1:1 port of the C++ backends. While they did serve as inspiration here and there, this implementation is mostly written from scratch. Imgui itself does a very good job with its API but the platforms it supports are usually a bit finicky. So some issues surely are to be expected.